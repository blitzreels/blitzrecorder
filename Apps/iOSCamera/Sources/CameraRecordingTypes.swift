import BlitzRecorderCore
@preconcurrency import AVFoundation
#if canImport(Cinematic)
import Cinematic
#endif
import Foundation

enum CameraCaptureError: LocalizedError {
    case sessionNotRunning
    case alreadyRecording
    case notRecording
    case recordingStartTimedOut
    case videoConnectionUnavailable
    case captureSettingsMismatch(String)
    case cinematicNotActive
    case cinematicHEVCUnavailable
    case cinematicHEVCNotActive(actual: String?)
    case cinematicApertureMismatch(expected: Double, actual: Double)
    case cameraPressureTooHigh(String)

    var errorDescription: String? {
        switch self {
        case .sessionNotRunning:
            "Camera session is not running."
        case .alreadyRecording:
            "Camera is already recording."
        case .notRecording:
            "Camera is not recording."
        case .recordingStartTimedOut:
            "Camera recording did not start in time."
        case .videoConnectionUnavailable:
            "Camera video connection is not available."
        case .captureSettingsMismatch(let reason):
            reason
        case .cinematicNotActive:
            "Cinematic was requested but is not active on the iPhone camera."
        case .cinematicHEVCUnavailable:
            "Cinematic needs HEVC recording quality, but HEVC is not available on the iPhone camera."
        case .cinematicHEVCNotActive(let actual):
            "Cinematic needs HEVC recording quality, but the iPhone camera output is \(actual ?? "not reporting HEVC")."
        case let .cinematicApertureMismatch(expected, actual):
            "Cinematic depth did not apply. Requested f/\(Self.formatAperture(expected)), got f/\(Self.formatAperture(actual))."
        case .cameraPressureTooHigh(let reason):
            reason
        }
    }

    private static func formatAperture(_ aperture: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.minimumIntegerDigits = 1
        return formatter.string(from: NSNumber(value: aperture)) ?? String(format: "%.1f", aperture)
    }
}

final class MovieRecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var startContinuation: CheckedContinuation<UInt64, Error>?
    private var startResult: Result<UInt64, Error>?
    private var didResolveStart = false
    var completion: (@Sendable (Result<URL, Error>) -> Void)?
    var unexpectedCompletion: (@Sendable (URL, Error?) -> Void)?
    var outputFileURL: URL?

    func waitForStart(timeoutSeconds: TimeInterval = 3) async throws -> UInt64 {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            let resolvedResult = startResult
            if resolvedResult == nil {
                startContinuation = continuation
                DispatchQueue.global(qos: .userInitiated).asyncAfter(
                    deadline: .now() + timeoutSeconds
                ) { [weak self] in
                    self?.resolveStart(.failure(CameraCaptureError.recordingStartTimedOut))
                }
            }
            lock.unlock()

            if let resolvedResult {
                switch resolvedResult {
                case .success(let startTime):
                    continuation.resume(returning: startTime)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        outputFileURL = fileURL
        resolveStart(.success(DispatchTime.now().uptimeNanoseconds))
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        self.outputFileURL = outputFileURL
        if let error {
            resolveStart(.failure(error))
        } else {
            resolveStart(.success(DispatchTime.now().uptimeNanoseconds))
        }
        guard let completion else {
            unexpectedCompletion?(outputFileURL, error)
            return
        }
        if let error {
            completion(.failure(error))
        } else {
            completion(.success(outputFileURL))
        }
    }

    private func resolveStart(_ result: Result<UInt64, Error>) {
        lock.lock()
        let continuation: CheckedContinuation<UInt64, Error>?
        if didResolveStart {
            continuation = nil
        } else {
            didResolveStart = true
            startResult = result
            continuation = startContinuation
            startContinuation = nil
        }
        lock.unlock()

        guard let continuation else { return }
        switch result {
        case .success(let startTime):
            continuation.resume(returning: startTime)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

struct CameraRecordingStartResult: Sendable {
    let url: URL
    let deviceStartTime: UInt64
    let diagnostics: RemoteCameraRecordingDiagnostics
}

struct CameraRecordingResult: Sendable {
    let url: URL
    let byteCount: Int64
    let durationSeconds: Double
    let stopReason: String?
    let recordingDiagnostics: RemoteCameraRecordingDiagnostics?

    init(
        url: URL,
        stopReason: String? = nil,
        recordingDiagnostics: RemoteCameraRecordingDiagnostics? = nil
    ) async throws {
        self.url = url
        self.stopReason = stopReason
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let asset = AVURLAsset(url: url)
        durationSeconds = CMTimeGetSeconds(try await asset.load(.duration))
        let fileDiagnostics = await Self.finishedMovieDiagnostics(
            for: asset,
            expectedDiagnostics: recordingDiagnostics
        )
        self.recordingDiagnostics = recordingDiagnostics?.merging(fileDiagnostics) ?? fileDiagnostics
    }

    private static func finishedMovieDiagnostics(
        for asset: AVAsset,
        expectedDiagnostics: RemoteCameraRecordingDiagnostics?
    ) async -> RemoteCameraRecordingDiagnostics? {
        var diagnostics = RemoteCameraRecordingDiagnostics()

        do {
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            if let videoTrack = videoTracks.first {
                let codecTypes = try await videoTrack.load(.formatDescriptions)
                    .map { codecLabel(for: CMFormatDescriptionGetMediaSubType($0)) }
                if !codecTypes.isEmpty {
                    diagnostics.recordedVideoCodecTypes = codecTypes
                }
            }
            diagnostics.recordedMetadataTrackCount = try await asset.loadTracks(withMediaType: .metadata).count
        } catch {
            diagnostics.captureWarning = RemoteCameraRecordingWarningAccumulator.mergedWarning(
                diagnostics.captureWarning,
                "Could not inspect saved iPhone movie metadata"
            )
        }

        if expectedDiagnostics?.cinematicVideoCaptureEnabled == true {
            await inspectFinishedCinematicAsset(asset, diagnostics: &diagnostics)
        }

        return diagnostics
    }

    private static func inspectFinishedCinematicAsset(
        _ asset: AVAsset,
        diagnostics: inout RemoteCameraRecordingDiagnostics
    ) async {
        #if canImport(Cinematic)
        if #available(iOS 17.0, *) {
            do {
                guard await CNAssetInfo.isCinematic(asset: asset) else {
                    diagnostics.cinematicAssetVerified = false
                    return
                }
                let assetInfo = try await CNAssetInfo(asset: asset)
                diagnostics.cinematicTrackCount = assetInfo.allCinematicTracks.count
                let requiredTrackIDs = [
                    assetInfo.cinematicVideoTrack.trackID,
                    assetInfo.cinematicDisparityTrack.trackID,
                    assetInfo.cinematicMetadataTrack.trackID
                ]
                let cinematicDuration = assetInfo.timeRange.duration.seconds
                if cinematicDuration.isFinite {
                    diagnostics.cinematicDurationSeconds = cinematicDuration
                }
                diagnostics.cinematicAssetVerified = !assetInfo.allCinematicTracks.isEmpty
                    && requiredTrackIDs.allSatisfy { $0 != 0 }
                    && cinematicDuration.isFinite
                    && cinematicDuration > 0
            } catch {
                diagnostics.cinematicAssetVerified = false
                diagnostics.captureWarning = RemoteCameraRecordingWarningAccumulator.mergedWarning(
                    diagnostics.captureWarning,
                    "Could not inspect saved Cinematic metadata"
                )
            }
        } else {
            diagnostics.captureWarning = RemoteCameraRecordingWarningAccumulator.mergedWarning(
                diagnostics.captureWarning,
                "iOS version cannot inspect saved Cinematic metadata"
            )
        }
        #else
        diagnostics.captureWarning = RemoteCameraRecordingWarningAccumulator.mergedWarning(
            diagnostics.captureWarning,
            "This iPhone build cannot inspect saved Cinematic metadata"
        )
        #endif
    }

    private static func codecLabel(for codec: FourCharCode) -> String {
        switch codec {
        case kCMVideoCodecType_HEVC:
            return "HEVC"
        case kCMVideoCodecType_H264:
            return "H.264"
        default:
            let scalars = [
                UnicodeScalar((codec >> 24) & 0xff),
                UnicodeScalar((codec >> 16) & 0xff),
                UnicodeScalar((codec >> 8) & 0xff),
                UnicodeScalar(codec & 0xff)
            ]
            let fourCC = scalars.compactMap { $0 }.map(String.init).joined()
            return fourCC.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "\(codec)"
                : fourCC
        }
    }
}

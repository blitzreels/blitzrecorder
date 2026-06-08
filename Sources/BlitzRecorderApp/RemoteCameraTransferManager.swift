import BlitzRecorderCore
import AVFoundation
import CoreMedia
#if canImport(Cinematic)
import Cinematic
#endif
import CryptoKit
import Foundation

@MainActor
final class RemoteCameraTransferManager {
    typealias ImportedMediaValidator = @MainActor (URL, RemoteCameraTransferManifest?) async throws -> [String]

    private struct TransferSession {
        let destinationURL: URL
        let partialURL: URL
        let fileHandle: FileHandle
        var expectedByteCount: Int64
        var manifest: RemoteCameraTransferManifest?
        var receivedByteCount: Int64
        var settings: RecordingSettings?
    }

    private let pendingImportStore: RemoteCameraPendingImportStore
    private let sendCommand: (RemoteCameraCommand) -> Void
    private let onMessage: (String) -> Void
    private let onTransferFinished: (UUID) -> Void
    private let validateImportedMedia: ImportedMediaValidator

    private var transfers: [UUID: TransferSession] = [:]
    private var continuations: [UUID: CheckedContinuation<MediaWriterCompletion, Error>] = [:]
    private var timeoutTasks: [UUID: Task<Void, Never>] = [:]

    init(
        pendingImportStore: RemoteCameraPendingImportStore = RemoteCameraPendingImportStore(),
        sendCommand: @escaping (RemoteCameraCommand) -> Void,
        onMessage: @escaping (String) -> Void,
        onTransferFinished: @escaping (UUID) -> Void,
        validateImportedMedia: @escaping ImportedMediaValidator = RemoteCameraTransferManager.validateImportedMedia
    ) {
        self.pendingImportStore = pendingImportStore
        self.sendCommand = sendCommand
        self.onMessage = onMessage
        self.onTransferFinished = onTransferFinished
        self.validateImportedMedia = validateImportedMedia
    }

    func registerPendingImport(
        takeID: UUID,
        serviceID: String?,
        take: RecordingTake,
        settings: RecordingSettings
    ) {
        pendingImportStore.upsert(RemoteCameraPendingImport(
            takeID: takeID,
            serviceID: serviceID,
            scratchDirectory: take.scratchDirectory,
            destinationURL: take.cameraURL,
            createdAt: Date(),
            expectedByteCount: nil
        ), settings: settings)
    }

    func removePendingImport(takeID: UUID, settings: RecordingSettings) {
        pendingImportStore.remove(takeID: takeID, settings: settings)
    }

    func takeID(activeTakeID: UUID?, take: RecordingTake, settings: RecordingSettings) -> UUID? {
        RemoteCameraTakeIDResolver.takeID(
            activeTakeID: activeTakeID,
            pendingTransferDestinationURLs: transfers.mapValues(\.destinationURL),
            pendingImports: pendingImportStore.all(settings: settings),
            take: take
        )
    }

    func hasCompletedImport(for take: RecordingTake) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: take.cameraURL.path),
              let size = attributes[.size] as? NSNumber else {
            return false
        }
        return size.int64Value > 0
    }

    func waitForStopAndImport(takeID: UUID, take: RecordingTake, settings: RecordingSettings) async throws -> MediaWriterCompletion {
        try await withCheckedThrowingContinuation { continuation in
            continuations[takeID] = continuation
            pendingImportStore.updatePhase(takeID: takeID, phase: .waitingForStop, settings: settings)
            if transfers[takeID] != nil {
                onMessage("Waiting for iPhone media download...")
                scheduleTimeout(
                    takeID: takeID,
                    reason: "Timed out while receiving iPhone recording data."
                )
                return
            }

            onMessage("Stopping iPhone recording...")
            sendCommand(.stop(RemoteCameraTimeline(
                takeID: takeID,
                hostStopTime: DispatchTime.now().uptimeNanoseconds
            )))
            let resumeOffset = beginTransfer(
                takeID: takeID,
                destinationURL: take.cameraURL,
                expectedByteCount: 0,
                settings: settings
            )
            guard let resumeOffset else { return }
            if resumeOffset > 0 {
                onMessage("iPhone media download will resume when the recording is ready.")
            }
        }
    }

    @discardableResult
    func beginTransfer(
        takeID: UUID,
        destinationURL: URL,
        expectedByteCount: Int64,
        settings: RecordingSettings? = nil
    ) -> Int64? {
        do {
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let partialURL = destinationURL.appendingPathExtension("partial")
            if !FileManager.default.fileExists(atPath: partialURL.path) {
                FileManager.default.createFile(atPath: partialURL.path, contents: nil)
            }
            let resumeOffset = (try? FileManager.default
                .attributesOfItem(atPath: partialURL.path)[.size] as? NSNumber)?
                .int64Value ?? 0
            let handle = try FileHandle(forWritingTo: partialURL)
            try handle.seek(toOffset: UInt64(resumeOffset))
            transfers[takeID] = TransferSession(
                destinationURL: destinationURL,
                partialURL: partialURL,
                fileHandle: handle,
                expectedByteCount: expectedByteCount,
                manifest: nil,
                receivedByteCount: resumeOffset,
                settings: settings
            )
            if let settings {
                pendingImportStore.updatePhase(takeID: takeID, phase: .transferring, settings: settings)
            }
            scheduleTimeout(
                takeID: takeID,
                reason: "Timed out waiting for iPhone recording transfer."
            )
            onMessage(resumeOffset > 0
                ? "Resuming iPhone media download..."
                : "Downloading iPhone media...")
            return resumeOffset
        } catch {
            finish(takeID: takeID, result: .failure(error))
            return nil
        }
    }

    func applyTransferReady(
        takeID: UUID,
        byteCount: Int64,
        manifest: RemoteCameraTransferManifest,
        settings: RecordingSettings,
        hostTimelineStartTime: UInt64?,
        estimatedHostStartTime: UInt64?
    ) {
        guard var transfer = transfers[takeID] else { return }
        var manifest = manifest
        manifest.hostTimelineStartTime = manifest.hostTimelineStartTime ?? hostTimelineStartTime
        manifest.estimatedHostStartTime = manifest.estimatedHostStartTime ?? estimatedHostStartTime

        if transfer.receivedByteCount > byteCount {
            try? transfer.fileHandle.truncate(atOffset: 0)
            try? transfer.fileHandle.seek(toOffset: 0)
            transfer.receivedByteCount = 0
        }

        transfer.expectedByteCount = byteCount
        transfer.manifest = manifest
        transfers[takeID] = transfer
        pendingImportStore.updatePhase(takeID: takeID, phase: .ready, settings: settings)
        pendingImportStore.updateExpectedByteCount(
            takeID: takeID,
            expectedByteCount: byteCount,
            settings: settings
        )
        scheduleTimeout(
            takeID: takeID,
            reason: "Timed out while receiving iPhone recording data."
        )
        let size = ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
        let diagnosticsSummary = Self.recordingDiagnosticsSummary(for: manifest)
        onMessage(
            diagnosticsSummary.map { "Downloading iPhone media (\(size)). \($0)" }
                ?? "Downloading iPhone media (\(size))..."
        )
        sendCommand(.requestTransfer(takeID: takeID, resumeOffset: transfer.receivedByteCount))
    }

    func writeChunk(takeID: UUID, offset: Int64, data: Data, isFinal: Bool) {
        guard var transfer = transfers[takeID] else {
            finish(takeID: takeID, result: .failure(RecorderError.remoteCameraTransferFailed("Transfer was not initialized.")))
            return
        }
        do {
            switch RemoteCameraTransferProtocol.chunkDisposition(
                offset: offset,
                receivedByteCount: transfer.receivedByteCount
            ) {
            case .append:
                break
            case .alreadyReceived(let acknowledgedByteCount):
                sendCommand(.transferAck(
                    takeID: takeID,
                    receivedByteCount: acknowledgedByteCount
                ))
                return
            case .gap(let expectedOffset, let receivedOffset):
                throw RecorderError.remoteCameraTransferFailed(
                    "Expected chunk at offset \(expectedOffset), received \(receivedOffset)."
                )
            }
            try transfer.fileHandle.seek(toOffset: UInt64(offset))
            try transfer.fileHandle.write(contentsOf: data)
            transfer.receivedByteCount = max(transfer.receivedByteCount, offset + Int64(data.count))
            transfers[takeID] = transfer
            sendCommand(.transferAck(
                takeID: takeID,
                receivedByteCount: transfer.receivedByteCount
            ))
            scheduleTimeout(
                takeID: takeID,
                reason: "Timed out while receiving iPhone recording data."
            )
            _ = isFinal
        } catch {
            finish(takeID: takeID, result: .failure(error))
        }
    }

    func completeTransfer(takeID: UUID, byteCount: Int64, sha256: String?, settings: RecordingSettings) async {
        guard let transfer = transfers[takeID] else { return }
        await finishCompletedTransfer(takeID: takeID, transfer: transfer, byteCount: byteCount, sha256: sha256, settings: settings)
    }

    func failInFlightTransfer(takeID: UUID, reason: String) {
        guard transfers[takeID] != nil || continuations[takeID] != nil else { return }
        finish(takeID: takeID, result: .failure(RecorderError.remoteCameraTransferFailed(reason)))
    }

    func requestPendingImports(serviceID: String, settings: RecordingSettings) {
        for pendingImport in pendingImportStore.all(settings: settings) {
            guard pendingImport.serviceID == nil || pendingImport.serviceID == serviceID else { continue }
            guard transfers[pendingImport.takeID] == nil else { continue }
            guard let resumeOffset = beginTransfer(
                takeID: pendingImport.takeID,
                destinationURL: pendingImport.destinationURL,
                expectedByteCount: pendingImport.expectedByteCount ?? 0,
                settings: settings
            ) else { continue }
            sendCommand(.requestTransfer(takeID: pendingImport.takeID, resumeOffset: resumeOffset))
        }
    }

    private func scheduleTimeout(takeID: UUID, reason: String) {
        timeoutTasks.removeValue(forKey: takeID)?.cancel()
        timeoutTasks[takeID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                self.timeoutTasks.removeValue(forKey: takeID)
                guard self.transfers[takeID] != nil || self.continuations[takeID] != nil else {
                    return
                }
                self.finish(
                    takeID: takeID,
                    result: .failure(RecorderError.remoteCameraTransferFailed(reason))
                )
            }
        }
    }

    private func finish(takeID: UUID, result: Result<MediaWriterCompletion, Error>) {
        timeoutTasks.removeValue(forKey: takeID)?.cancel()
        if let transfer = transfers.removeValue(forKey: takeID) {
            if let settings = transfer.settings {
                pendingImportStore.updatePhase(takeID: takeID, phase: .failedRecoverable, settings: settings)
            }
            try? transfer.fileHandle.close()
        }
        onTransferFinished(takeID)
        guard let continuation = continuations.removeValue(forKey: takeID) else {
            return
        }
        switch result {
        case .success(let completion):
            continuation.resume(returning: completion)
        case .failure(let error):
            sendCommand(.cancel)
            continuation.resume(throwing: error)
        }
    }

    private func finishCompletedTransfer(
        takeID: UUID,
        transfer: TransferSession,
        byteCount: Int64,
        sha256: String?,
        settings: RecordingSettings
    ) async {
        timeoutTasks.removeValue(forKey: takeID)?.cancel()
        do {
            try transfer.fileHandle.synchronize()
            try transfer.fileHandle.close()
            transfers.removeValue(forKey: takeID)
            let importedByteCount = (try FileManager.default
                .attributesOfItem(atPath: transfer.partialURL.path)[.size] as? NSNumber)?
                .int64Value ?? 0
            guard importedByteCount == byteCount else {
                throw RecorderError.remoteCameraTransferFailed("Expected \(byteCount) bytes, imported \(importedByteCount).")
            }
            if let sha256 {
                let importedSHA256 = try Self.sha256HexDigest(for: transfer.partialURL)
                guard importedSHA256 == sha256 else {
                    throw RecorderError.remoteCameraTransferFailed("Checksum mismatch.")
                }
            }
            let validationWarnings = try await validateImportedMedia(transfer.partialURL, transfer.manifest)
            if FileManager.default.fileExists(atPath: transfer.destinationURL.path) {
                try FileManager.default.removeItem(at: transfer.destinationURL)
            }
            try FileManager.default.moveItem(at: transfer.partialURL, to: transfer.destinationURL)
            try Self.writeManifest(transfer.manifest, destinationURL: transfer.destinationURL, sha256: sha256)
            validationWarnings.forEach { warning in
                onMessage("iPhone media warning: \(warning)")
            }
            pendingImportStore.updatePhase(takeID: takeID, phase: .complete, settings: settings)
            pendingImportStore.remove(takeID: takeID, settings: settings)
            sendCommand(.transferAck(takeID: takeID, receivedByteCount: byteCount))
            onTransferFinished(takeID)
            guard let continuation = continuations.removeValue(forKey: takeID) else {
                onMessage("Recovered Remote iPhone camera import: \(transfer.destinationURL.path)")
                return
            }
            continuation.resume(returning: .wrote(transfer.destinationURL))
        } catch {
            onMessage("iPhone media import failed: \(error.localizedDescription)")
            pendingImportStore.updatePhase(takeID: takeID, phase: .failedRecoverable, settings: settings)
            transfers.removeValue(forKey: takeID)
            onTransferFinished(takeID)
            if let continuation = continuations.removeValue(forKey: takeID) {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func sha256HexDigest(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            guard !data.isEmpty else { break }
            hasher.update(data: data)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func writeManifest(
        _ manifest: RemoteCameraTransferManifest?,
        destinationURL: URL,
        sha256: String?
    ) throws {
        guard var manifest else { return }
        manifest.sha256 = sha256 ?? manifest.sha256
        let sidecarURL = destinationURL
            .deletingPathExtension()
            .appendingPathExtension("remote-camera-manifest.json")
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: sidecarURL, options: [.atomic])
    }

    static func validateImportedMedia(
        url: URL,
        manifest: RemoteCameraTransferManifest?
    ) async throws -> [String] {
        let asset = AVURLAsset(url: url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw RecorderError.remoteCameraTransferFailed("Imported iPhone recording has no video track.")
        }

        let durationSeconds = try await asset.load(.duration).seconds
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            throw RecorderError.remoteCameraTransferFailed("Imported iPhone recording has an invalid duration.")
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        guard naturalSize.width > 0, naturalSize.height > 0 else {
            throw RecorderError.remoteCameraTransferFailed("Imported iPhone recording has invalid video dimensions.")
        }

        if let expectedDuration = manifest?.durationSeconds,
           expectedDuration.isFinite,
           expectedDuration > 0 {
            let tolerance = max(0.75, expectedDuration * 0.05)
            guard abs(durationSeconds - expectedDuration) <= tolerance else {
                throw RecorderError.remoteCameraTransferFailed(
                    "Imported iPhone recording duration mismatch. Expected \(formattedSeconds(expectedDuration)), got \(formattedSeconds(durationSeconds))."
                )
            }
        }

        var warnings: [String] = []
        if manifest?.settings.cinematicVideoEnabled == true,
           manifest?.format?.supportsCinematicVideo == false {
            throw RecorderError.remoteCameraTransferFailed(
                "Imported iPhone recording manifest says Cinematic was requested, but the recording format was not Cinematic-capable."
            )
        }
        let metadataTracks = try await asset.loadTracks(withMediaType: .metadata)
        if manifest?.recordingDiagnostics?.recordsOrientationAndMirroringChangesAsMetadataTrack == true,
           metadataTracks.isEmpty {
            throw RecorderError.remoteCameraTransferFailed(
                "Imported iPhone recording is missing the orientation metadata track needed for WYSIWYG rotation."
            )
        }
        if manifest?.recordingDiagnostics?.recordsOrientationAndMirroringChangesAsMetadataTrack == false,
           manifest?.settings.usesAutomaticRotation == true {
            throw RecorderError.remoteCameraTransferFailed(
                "Automatic iPhone rotation was enabled, but the recording did not include orientation metadata."
            )
        }
        if let requestedRotationDegrees = manifest?.settings.rotationDegrees,
           let captureRotationDegrees = manifest?.recordingDiagnostics?.captureRotationDegrees,
           RemoteCameraSettings.normalizedRotationDegrees(requestedRotationDegrees)
                != RemoteCameraSettings.normalizedRotationDegrees(captureRotationDegrees) {
            throw RecorderError.remoteCameraTransferFailed(
                "Imported iPhone recording rotation mismatch. Expected \(RemoteCameraSettings.normalizedRotationDegrees(requestedRotationDegrees)) degrees, got \(RemoteCameraSettings.normalizedRotationDegrees(captureRotationDegrees)) degrees."
            )
        }
        if manifest?.settings.cinematicVideoEnabled == true,
           manifest?.recordingDiagnostics?.cinematicVideoCaptureEnabled != true {
            warnings.append("Cinematic was requested but the imported manifest does not prove it was active")
        }
        if manifest?.settings.cinematicVideoEnabled == true,
           manifest?.recordingDiagnostics?.cinematicVideoCaptureEnabled == true,
           manifest?.recordingDiagnostics?.cinematicAssetVerified == false {
            throw RecorderError.remoteCameraTransferFailed(
                "The iPhone saved this take without Cinematic depth metadata."
            )
        }
        if manifest?.settings.cinematicVideoEnabled == true,
           let codecLabel = try await videoCodecLabel(for: videoTrack),
           !codecLabel.localizedCaseInsensitiveContains("HEVC") {
            let message = "Cinematic recording used \(codecLabel); HEVC is required for iPhone-quality Cinematic recordings"
            if manifest?.recordingDiagnostics?.cinematicVideoCaptureEnabled == true {
                throw RecorderError.remoteCameraTransferFailed(message)
            }
            warnings.append(message)
        }
        if manifest?.settings.cinematicVideoEnabled == true,
           manifest?.recordingDiagnostics?.cinematicVideoCaptureEnabled == true {
            try await validateImportedCinematicAsset(asset)
        }
        return warnings
    }

    private static func validateImportedCinematicAsset(_ asset: AVAsset) async throws {
        #if canImport(Cinematic)
        guard await CNAssetInfo.isCinematic(asset: asset) else {
            throw RecorderError.remoteCameraTransferFailed(
                "Imported iPhone recording is not a Cinematic asset; depth metadata was lost."
            )
        }

        let assetInfo = try await CNAssetInfo(asset: asset)
        guard !assetInfo.allCinematicTracks.isEmpty else {
            throw RecorderError.remoteCameraTransferFailed(
                "Imported iPhone recording has no Cinematic tracks."
            )
        }
        let requiredTrackIDs = [
            assetInfo.cinematicVideoTrack.trackID,
            assetInfo.cinematicDisparityTrack.trackID,
            assetInfo.cinematicMetadataTrack.trackID
        ]
        guard requiredTrackIDs.allSatisfy({ $0 != 0 }) else {
            throw RecorderError.remoteCameraTransferFailed(
                "Imported iPhone recording is missing a Cinematic video, disparity, or metadata track."
            )
        }

        let cinematicDuration = assetInfo.timeRange.duration.seconds
        guard cinematicDuration.isFinite, cinematicDuration > 0 else {
            throw RecorderError.remoteCameraTransferFailed(
                "Imported iPhone recording has invalid Cinematic timing metadata."
            )
        }
        #else
        throw RecorderError.remoteCameraTransferFailed(
            "This Mac build cannot validate Cinematic iPhone recordings because the Cinematic framework is unavailable."
        )
        #endif
    }

    static func recordingDiagnosticsSummary(for manifest: RemoteCameraTransferManifest) -> String? {
        var messages: [String] = []
        let diagnostics = manifest.recordingDiagnostics

        if let expectedFormatID = manifest.settings.formatID,
           let captureFormatID = diagnostics?.captureFormatID,
           captureFormatID != expectedFormatID {
            messages.append("iPhone recorded \(captureFormatID), requested \(expectedFormatID).")
        }
        if let captureFrameRate = diagnostics?.captureFrameRate,
           manifest.settings.frameRate > 0,
           captureFrameRate > 0,
           captureFrameRate != manifest.settings.frameRate {
            messages.append("iPhone recorded \(captureFrameRate) fps, requested \(manifest.settings.frameRate) fps.")
        }
        if let captureColorMode = diagnostics?.captureColorMode,
           captureColorMode != manifest.settings.colorMode {
            messages.append(
                "iPhone recorded \(captureColorMode.displayName) color, requested \(manifest.settings.colorMode.displayName)."
            )
        }
        if let captureRotationDegrees = diagnostics?.captureRotationDegrees {
            let requestedRotationDegrees = RemoteCameraSettings.normalizedRotationDegrees(
                manifest.settings.rotationDegrees
            )
            if captureRotationDegrees != requestedRotationDegrees {
                messages.append(
                    "iPhone recorded \(captureRotationDegrees) degree rotation, requested \(requestedRotationDegrees) degrees."
                )
            }
        } else if diagnostics?.observedAtDeviceStartTime != nil {
            messages.append("Rotation was not reported by the iPhone recording.")
        }
        if manifest.settings.stabilizationMode != .off {
            if let captureStabilizationMode = diagnostics?.captureStabilizationMode {
                if !stabilizationMatches(
                    requested: manifest.settings.stabilizationMode,
                    captured: captureStabilizationMode
                ) {
                    messages.append(
                        "iPhone recorded \(captureStabilizationMode.displayName) stabilization, requested \(manifest.settings.stabilizationMode.displayName)."
                    )
                }
            } else if diagnostics?.observedAtDeviceStartTime != nil {
                messages.append("Stabilization mode was not reported by the iPhone recording.")
            }
        }

        if manifest.settings.cinematicVideoEnabled {
            switch diagnostics?.cinematicVideoCaptureEnabled {
            case .some(true):
                break
            case .some(false):
                messages.append("Cinematic was requested but was not active on the iPhone recording.")
            case .none:
                messages.append("Cinematic status was not reported by the iPhone recording.")
            }
            if manifest.format?.supportsCinematicVideo == false {
                messages.append("Recording format was not Cinematic-capable.")
            }
            if diagnostics?.cinematicVideoCaptureEnabled == true,
               diagnostics?.cinematicFocusMetadataEnabled == false {
                messages.append("Cinematic focus metadata was unavailable during recording.")
            }
            if diagnostics?.cinematicVideoCaptureEnabled == true,
               diagnostics?.cinematicAssetVerified == false {
                messages.append("The saved iPhone movie did not contain Cinematic depth metadata.")
            }
            if let codecLabel = manifest.captureCodecLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
               !codecLabel.isEmpty,
               !codecLabel.localizedCaseInsensitiveContains("HEVC") {
                messages.append(
                    "Cinematic recorded with \(codecLabel); HEVC is recommended for iPhone-quality Cinematic recordings."
                )
            }
            if diagnostics?.firstOrderAmbisonicsAudioSupported == true,
               diagnostics?.firstOrderAmbisonicsAudioEnabled != true {
                messages.append("Spatial audio was supported but not enabled for this Cinematic recording.")
            }

            if let requestedAperture = manifest.settings.cinematicAperture {
                if let recordedAperture = diagnostics?.simulatedAperture {
                    if abs(recordedAperture - requestedAperture) > 0.05 {
                        messages.append(
                            "Depth of field recorded at f/\(formattedAperture(recordedAperture)), requested f/\(formattedAperture(requestedAperture))."
                        )
                    }
                } else {
                    messages.append("Depth of field aperture was not reported by the iPhone recording.")
                }
            }
        }

        if diagnostics?.recordsOrientationAndMirroringChangesAsMetadataTrack == false {
            messages.append("Orientation metadata was not recorded; rotation may need manual correction.")
        }

        if let captureWarning = diagnostics?.captureWarning, !captureWarning.isEmpty {
            messages.append(captureWarning)
        }

        return messages.isEmpty ? nil : messages.joined(separator: " ")
    }

    private static func stabilizationMatches(
        requested: RemoteCameraStabilizationMode,
        captured: RemoteCameraStabilizationMode
    ) -> Bool {
        switch requested {
        case .off:
            return captured == .off
        case .auto:
            return captured != .off
        case .standard:
            return captured == requested
        case .cinematic:
            return captured == .cinematic || captured == .cinematicExtendedEnhanced
        case .cinematicExtendedEnhanced:
            return captured == .cinematicExtendedEnhanced
        }
    }

    private static func videoCodecLabel(for videoTrack: AVAssetTrack) async throws -> String? {
        let formatDescriptions = try await videoTrack.load(.formatDescriptions)
        guard let formatDescription = formatDescriptions.first else {
            return nil
        }
        return videoCodecLabel(for: CMFormatDescriptionGetMediaSubType(formatDescription))
    }

    private static func videoCodecLabel(for codec: FourCharCode) -> String {
        switch codec {
        case kCMVideoCodecType_HEVC:
            return "HEVC"
        case kCMVideoCodecType_H264:
            return "H.264"
        case kCMVideoCodecType_AppleProRes422:
            return "ProRes 422"
        case kCMVideoCodecType_AppleProRes4444:
            return "ProRes 4444"
        default:
            return fourCharacterCode(codec)
        }
    }

    private static func fourCharacterCode(_ value: FourCharCode) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
        let scalars = bytes.map { byte -> UnicodeScalar in
            let scalar = byte >= 32 && byte <= 126 ? byte : UInt8(ascii: "?")
            return UnicodeScalar(scalar)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func formattedAperture(_ aperture: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.minimumIntegerDigits = 1
        return formatter.string(from: NSNumber(value: aperture)) ?? String(format: "%.1f", aperture)
    }

    private static func formattedSeconds(_ seconds: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.minimumIntegerDigits = 1
        return formatter.string(from: NSNumber(value: seconds)) ?? String(format: "%.2f", seconds)
    }
}

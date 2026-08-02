import AVFoundation
import CoreMedia
import Foundation
import VideoToolbox

struct OptimizedVideoSettingsRequest {
    let width: Int
    let height: Int
    let bitrate: Int
    let framesPerSecond: Int
    let hardwareEncoderAvailable: Bool
}

enum OptimizedCompositionExporter {
    static func export(
        composition: AVComposition,
        videoComposition: AVVideoComposition,
        audioMix: AVAudioMix?,
        outputURL: URL,
        outputFileType: AVFileType,
        renderSize: CGSize,
        settings: RecordingSettings,
        duration: CMTime,
        progressHandler: (@MainActor (Double) -> Void)? = nil
    ) async throws {
        try? FileManager.default.removeItem(at: outputURL)

        let reader = try AVAssetReader(asset: composition)
        let videoTracks = composition.tracks(withMediaType: .video)
        guard !videoTracks.isEmpty else {
            throw RecorderError.exportUnavailable
        }

        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: videoTracks,
            videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )
        videoOutput.videoComposition = videoComposition
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else {
            throw RecorderError.exportUnavailable
        }
        reader.add(videoOutput)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: outputFileType)
        writer.shouldOptimizeForNetworkUse = true

        let width = Int(renderSize.width.rounded())
        let height = Int(renderSize.height.rounded())
        let hardwareEncoderStatus = HardwareVideoEncoderSupport.probe(
            HardwareVideoEncoderProbeRequest(
                width: width,
                height: height,
                codecType: kCMVideoCodecType_HEVC
            )
        )
        let videoSettings = videoOutputSettings(
            for: OptimizedVideoSettingsRequest(
                width: width,
                height: height,
                bitrate: settings.finalVideoBitrate,
                framesPerSecond: settings.framesPerSecond,
                hardwareEncoderAvailable: hardwareEncoderStatus.isAvailable
            )
        )
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: videoSettings
        )
        guard writer.canAdd(videoInput) else {
            throw RecorderError.writerNotReady
        }
        writer.add(videoInput)

        let audioTracks = composition.tracks(withMediaType: .audio)
        let audioOutput: AVAssetReaderAudioMixOutput?
        let audioInput: AVAssetWriterInput?
        if !audioTracks.isEmpty {
            let output = AVAssetReaderAudioMixOutput(
                audioTracks: audioTracks,
                audioSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM
                ]
            )
            output.audioMix = audioMix
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else {
                throw RecorderError.exportUnavailable
            }
            reader.add(output)

            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: settings.finalAudioBitrate
                ]
            )
            guard writer.canAdd(input) else {
                throw RecorderError.writerNotReady
            }
            writer.add(input)
            audioOutput = output
            audioInput = input
        } else {
            audioOutput = nil
            audioInput = nil
        }

        guard writer.startWriting(), reader.startReading() else {
            throw writer.error ?? reader.error ?? RecorderError.writerNotReady
        }
        writer.startSession(atSourceTime: .zero)
        let performanceMonitor = ExportPerformanceMonitor(
            configuration: ExportPerformanceConfiguration(
                renderSize: renderSize,
                framesPerSecond: settings.framesPerSecond,
                hardwareEncoderStatus: hardwareEncoderStatus
            )
        )

        try await run(
            reader: reader,
            writer: writer,
            videoOutput: videoOutput,
            videoInput: videoInput,
            audioOutput: audioOutput,
            audioInput: audioInput,
            duration: duration,
            performanceMonitor: performanceMonitor,
            progressHandler: progressHandler
        )
        _ = performanceMonitor.finish(outputURL: outputURL)
    }

    static func videoOutputSettings(for request: OptimizedVideoSettingsRequest) -> [String: Any] {
        var outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: request.width,
            AVVideoHeightKey: request.height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: request.bitrate,
                AVVideoExpectedSourceFrameRateKey: request.framesPerSecond,
                AVVideoAllowFrameReorderingKey: true,
                AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel as String,
                kVTCompressionPropertyKey_RealTime as String: false
            ]
        ]
        if request.hardwareEncoderAvailable {
            outputSettings[AVVideoEncoderSpecificationKey] = [
                kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true
            ]
        }
        return outputSettings
    }

    private static func run(
        reader: AVAssetReader,
        writer: AVAssetWriter,
        videoOutput: AVAssetReaderOutput,
        videoInput: AVAssetWriterInput,
        audioOutput: AVAssetReaderOutput?,
        audioInput: AVAssetWriterInput?,
        duration: CMTime,
        performanceMonitor: ExportPerformanceMonitor,
        progressHandler: (@MainActor (Double) -> Void)?
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let state = ExportState(
                reader: reader,
                writer: writer,
                hasAudio: audioOutput != nil,
                performanceMonitor: performanceMonitor,
                continuation: continuation
            )
            let videoPump = ExportSamplePump(
                output: videoOutput,
                input: videoInput,
                writer: writer,
                state: state,
                durationSeconds: max(0.001, duration.seconds),
                performanceMonitor: performanceMonitor,
                progressHandler: progressHandler
            )

            videoInput.requestMediaDataWhenReady(on: DispatchQueue(label: "blitzrecorder.optimized-export.video")) {
                videoPump.pumpVideo()
            }

            guard let audioOutput, let audioInput else { return }
            let audioPump = ExportSamplePump(
                output: audioOutput,
                input: audioInput,
                writer: writer,
                state: state,
                durationSeconds: max(0.001, duration.seconds),
                performanceMonitor: performanceMonitor,
                progressHandler: nil
            )
            audioInput.requestMediaDataWhenReady(on: DispatchQueue(label: "blitzrecorder.optimized-export.audio")) {
                audioPump.pumpAudio()
            }
        }
    }
}

private final class ExportSamplePump: @unchecked Sendable {
    private let output: AVAssetReaderOutput
    private let input: AVAssetWriterInput
    private let writer: AVAssetWriter
    private let state: ExportState
    private let durationSeconds: Double
    private let performanceMonitor: ExportPerformanceMonitor?
    private let progressHandler: (@MainActor (Double) -> Void)?

    init(
        output: AVAssetReaderOutput,
        input: AVAssetWriterInput,
        writer: AVAssetWriter,
        state: ExportState,
        durationSeconds: Double,
        performanceMonitor: ExportPerformanceMonitor?,
        progressHandler: (@MainActor (Double) -> Void)?
    ) {
        self.output = output
        self.input = input
        self.writer = writer
        self.state = state
        self.durationSeconds = durationSeconds
        self.performanceMonitor = performanceMonitor
        self.progressHandler = progressHandler
    }

    func pumpVideo() {
        while input.isReadyForMoreMediaData {
            guard !state.isCompleted else { return }
            let readStartedAt = ProcessInfo.processInfo.systemUptime
            let nextSampleBuffer = output.copyNextSampleBuffer()
            performanceMonitor?.recordVideoRead(
                duration: ProcessInfo.processInfo.systemUptime - readStartedAt
            )
            guard let sampleBuffer = nextSampleBuffer else {
                input.markAsFinished()
                state.markVideoFinished()
                return
            }
            let appendStartedAt = ProcessInfo.processInfo.systemUptime
            let appended = input.append(sampleBuffer)
            performanceMonitor?.recordVideoAppend(
                duration: ProcessInfo.processInfo.systemUptime - appendStartedAt
            )
            if !appended {
                state.fail(writer.error ?? RecorderError.mediaWriteFailed("Final video writer rejected a video frame."))
                return
            }
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            performanceMonitor?.didWriteVideoFrame(at: presentationTime)
            if presentationTime.isValid {
                let progress = min(0.99, max(0, presentationTime.seconds / durationSeconds))
                Task { @MainActor in
                    progressHandler?(progress)
                }
            }
        }
    }

    func pumpAudio() {
        while input.isReadyForMoreMediaData {
            guard !state.isCompleted else { return }
            let readStartedAt = ProcessInfo.processInfo.systemUptime
            let nextSampleBuffer = output.copyNextSampleBuffer()
            performanceMonitor?.recordAudioRead(
                duration: ProcessInfo.processInfo.systemUptime - readStartedAt
            )
            guard let sampleBuffer = nextSampleBuffer else {
                input.markAsFinished()
                state.markAudioFinished()
                return
            }
            let appendStartedAt = ProcessInfo.processInfo.systemUptime
            let appended = input.append(sampleBuffer)
            performanceMonitor?.recordAudioAppend(
                duration: ProcessInfo.processInfo.systemUptime - appendStartedAt
            )
            if !appended {
                state.fail(writer.error ?? RecorderError.mediaWriteFailed("Final video writer rejected an audio sample."))
                return
            }
        }
    }
}

private final class ExportState: @unchecked Sendable {
    private let reader: AVAssetReader
    private let writer: AVAssetWriter
    private let continuation: CheckedContinuation<Void, Error>
    private let performanceMonitor: ExportPerformanceMonitor
    private let lock = DispatchQueue(label: "blitzrecorder.optimized-export.state")
    private var videoFinished = false
    private var audioFinished: Bool
    private var completed = false

    init(
        reader: AVAssetReader,
        writer: AVAssetWriter,
        hasAudio: Bool,
        performanceMonitor: ExportPerformanceMonitor,
        continuation: CheckedContinuation<Void, Error>
    ) {
        self.reader = reader
        self.writer = writer
        self.performanceMonitor = performanceMonitor
        self.continuation = continuation
        audioFinished = !hasAudio
    }

    var isCompleted: Bool {
        lock.sync { completed }
    }

    func markVideoFinished() {
        lock.async {
            self.videoFinished = true
            self.finishIfReady()
        }
    }

    func markAudioFinished() {
        lock.async {
            self.audioFinished = true
            self.finishIfReady()
        }
    }

    func fail(_ error: Error) {
        lock.async {
            guard !self.completed else { return }
            self.completed = true
            self.reader.cancelReading()
            self.writer.cancelWriting()
            self.continuation.resume(throwing: error)
        }
    }

    private func finishIfReady() {
        guard videoFinished, audioFinished, !completed else { return }
        completed = true
        if reader.status == .failed {
            writer.cancelWriting()
            continuation.resume(throwing: reader.error ?? RecorderError.exportUnavailable)
            return
        }
        let finalizationStartedAt = ProcessInfo.processInfo.systemUptime
        writer.finishWriting { [self] in
            performanceMonitor.recordWriterFinalization(
                duration: ProcessInfo.processInfo.systemUptime - finalizationStartedAt
            )
            if self.writer.status == .completed {
                self.continuation.resume()
            } else {
                self.continuation.resume(throwing: self.writer.error ?? RecorderError.writerNotReady)
            }
        }
    }
}

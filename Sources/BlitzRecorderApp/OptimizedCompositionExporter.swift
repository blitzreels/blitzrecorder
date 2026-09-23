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
    var codec: ExportVideoCodec = .hevc
    var compressionQuality: Float?
    var usesAverageBitRate: Bool = true
    var maxKeyFrameInterval: Int?

    init(
        width: Int,
        height: Int,
        bitrate: Int,
        framesPerSecond: Int,
        hardwareEncoderAvailable: Bool,
        codec: ExportVideoCodec = .hevc,
        compressionQuality: Float? = nil,
        usesAverageBitRate: Bool = true,
        maxKeyFrameInterval: Int? = nil
    ) {
        self.width = width
        self.height = height
        self.bitrate = bitrate
        self.framesPerSecond = framesPerSecond
        self.hardwareEncoderAvailable = hardwareEncoderAvailable
        self.codec = codec
        self.compressionQuality = compressionQuality
        self.usesAverageBitRate = usesAverageBitRate
        self.maxKeyFrameInterval = maxKeyFrameInterval
    }

    init(
        width: Int,
        height: Int,
        framesPerSecond: Int,
        hardwareEncoderAvailable: Bool,
        encoding: ExportEncodingProfile
    ) {
        self.init(
            width: width,
            height: height,
            bitrate: encoding.bitrate,
            framesPerSecond: framesPerSecond,
            hardwareEncoderAvailable: hardwareEncoderAvailable,
            codec: encoding.codec,
            compressionQuality: encoding.quality,
            usesAverageBitRate: encoding.usesAverageBitRate,
            maxKeyFrameInterval: encoding.maxKeyFrameInterval
        )
    }
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
        try Task.checkCancellation()
        try? FileManager.default.removeItem(at: outputURL)

        let reader = try AVAssetReader(asset: composition)
        let videoTracks = composition.tracks(withMediaType: .video)
        guard !videoTracks.isEmpty else {
            throw RecorderError.exportUnavailable
        }

        let encoding = settings.exportEncoding ?? .hevc(
            bitrate: settings.finalVideoBitrate,
            audioBitrate: settings.finalAudioBitrate
        )
        let pixelFormat: OSType = encoding.prefersFullRangeRGB
            ? kCVPixelFormatType_32BGRA
            : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: videoTracks,
            videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
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
                codecType: encoding.codec.cmCodecType
            )
        )
        let videoSettings = videoOutputSettings(
            for: OptimizedVideoSettingsRequest(
                width: width,
                height: height,
                framesPerSecond: settings.framesPerSecond,
                hardwareEncoderAvailable: hardwareEncoderStatus.isAvailable,
                encoding: encoding
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
            output.audioTimePitchAlgorithm = .spectral
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
                    AVEncoderBitRateKey: encoding.audioBitrate
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
            AVVideoCodecKey: request.codec.avCodec,
            AVVideoWidthKey: request.width,
            AVVideoHeightKey: request.height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ]
        ]
        var compression: [String: Any] = [
            AVVideoExpectedSourceFrameRateKey: request.framesPerSecond,
            kVTCompressionPropertyKey_RealTime as String: false
        ]
        if request.codec.isMezzanine {
            outputSettings[AVVideoCompressionPropertiesKey] = compression
        } else {
            compression[AVVideoAllowFrameReorderingKey] = true
            if let profileLevel = request.codec.profileLevel {
                compression[AVVideoProfileLevelKey] = profileLevel
            }
            if request.usesAverageBitRate {
                compression[AVVideoAverageBitRateKey] = request.bitrate
            }
            if let quality = request.compressionQuality {
                compression[kVTCompressionPropertyKey_Quality as String] = quality
            }
            compression[kVTCompressionPropertyKey_DataRateLimits as String] = [
                request.bitrate / 8,
                1
            ]
            if let maxKeyFrameInterval = request.maxKeyFrameInterval {
                compression[AVVideoMaxKeyFrameIntervalKey] = maxKeyFrameInterval
            }
            outputSettings[AVVideoCompressionPropertiesKey] = compression
        }
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
        let state = ExportState((
            reader: reader, writer: writer, hasAudio: audioOutput != nil,
            performanceMonitor: performanceMonitor
        ))
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.attach(continuation)
                guard !state.isCompleted else { return }
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
        } onCancel: {
            state.fail(CancellationError())
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
    private var continuation: CheckedContinuation<Void, Error>?
    private var result: Result<Void, Error>?
    private let performanceMonitor: ExportPerformanceMonitor
    private let lock = DispatchQueue(label: "blitzrecorder.optimized-export.state")
    private var videoFinished = false
    private var audioFinished: Bool
    private var completed = false

    init(_ configuration: (
        reader: AVAssetReader,
        writer: AVAssetWriter,
        hasAudio: Bool,
        performanceMonitor: ExportPerformanceMonitor
    )) {
        reader = configuration.reader
        writer = configuration.writer
        performanceMonitor = configuration.performanceMonitor
        audioFinished = !configuration.hasAudio
    }

    func attach(_ continuation: CheckedContinuation<Void, Error>) {
        lock.sync {
            if let result {
                continuation.resume(with: result)
            } else {
                self.continuation = continuation
            }
        }
    }

    private func resolve(_ result: Result<Void, Error>) {
        guard self.result == nil else { return }
        self.result = result
        continuation?.resume(with: result)
        continuation = nil
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
            self.resolve(.failure(error))
        }
    }

    private func finishIfReady() {
        guard videoFinished, audioFinished, !completed else { return }
        completed = true
        if reader.status == .failed {
            writer.cancelWriting()
            resolve(.failure(reader.error ?? RecorderError.exportUnavailable))
            return
        }
        let finalizationStartedAt = ProcessInfo.processInfo.systemUptime
        writer.finishWriting { [self] in
            performanceMonitor.recordWriterFinalization(
                duration: ProcessInfo.processInfo.systemUptime - finalizationStartedAt
            )
            lock.async {
                if self.writer.status == .completed {
                    self.resolve(.success(()))
                } else {
                    self.resolve(.failure(self.writer.error ?? RecorderError.writerNotReady))
                }
            }
        }
    }
}

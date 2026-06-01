import AVFoundation
import CoreMedia
import Foundation
import VideoToolbox

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
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
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
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: settings.finalVideoBitrate,
                    AVVideoExpectedSourceFrameRateKey: settings.framesPerSecond,
                    AVVideoAllowFrameReorderingKey: false,
                    AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel as String
                ]
            ]
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

        try await run(
            reader: reader,
            writer: writer,
            videoOutput: videoOutput,
            videoInput: videoInput,
            audioOutput: audioOutput,
            audioInput: audioInput,
            duration: duration,
            progressHandler: progressHandler
        )
    }

    private static func run(
        reader: AVAssetReader,
        writer: AVAssetWriter,
        videoOutput: AVAssetReaderOutput,
        videoInput: AVAssetWriterInput,
        audioOutput: AVAssetReaderOutput?,
        audioInput: AVAssetWriterInput?,
        duration: CMTime,
        progressHandler: (@MainActor (Double) -> Void)?
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let state = ExportState(
                reader: reader,
                writer: writer,
                hasAudio: audioOutput != nil,
                continuation: continuation
            )
            let videoPump = ExportSamplePump(
                output: videoOutput,
                input: videoInput,
                writer: writer,
                state: state,
                durationSeconds: max(0.001, duration.seconds),
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
    private let progressHandler: (@MainActor (Double) -> Void)?

    init(
        output: AVAssetReaderOutput,
        input: AVAssetWriterInput,
        writer: AVAssetWriter,
        state: ExportState,
        durationSeconds: Double,
        progressHandler: (@MainActor (Double) -> Void)?
    ) {
        self.output = output
        self.input = input
        self.writer = writer
        self.state = state
        self.durationSeconds = durationSeconds
        self.progressHandler = progressHandler
    }

    func pumpVideo() {
        while input.isReadyForMoreMediaData {
            guard !state.isCompleted else { return }
            guard let sampleBuffer = output.copyNextSampleBuffer() else {
                input.markAsFinished()
                state.markVideoFinished()
                return
            }
            if !input.append(sampleBuffer) {
                state.fail(writer.error ?? RecorderError.mediaWriteFailed("Final video writer rejected a video frame."))
                return
            }
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
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
            guard let sampleBuffer = output.copyNextSampleBuffer() else {
                input.markAsFinished()
                state.markAudioFinished()
                return
            }
            if !input.append(sampleBuffer) {
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
    private let lock = DispatchQueue(label: "blitzrecorder.optimized-export.state")
    private var videoFinished = false
    private var audioFinished: Bool
    private var completed = false

    init(
        reader: AVAssetReader,
        writer: AVAssetWriter,
        hasAudio: Bool,
        continuation: CheckedContinuation<Void, Error>
    ) {
        self.reader = reader
        self.writer = writer
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
        writer.finishWriting { [self] in
            if self.writer.status == .completed {
                self.continuation.resume()
            } else {
                self.continuation.resume(throwing: self.writer.error ?? RecorderError.writerNotReady)
            }
        }
    }
}

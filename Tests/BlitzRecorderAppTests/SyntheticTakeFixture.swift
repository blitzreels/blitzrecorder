import AVFoundation
import CoreGraphics
import XCTest
@testable import BlitzRecorderApp

/// A short screen + camera + microphone take written at test time, so export and editing
/// regressions run in CI without a real recording. The microphone holds a tone broken by two
/// silent gaps; the transcript covers the first and last tone, leaving the middle one as unspoken sound.
final class SyntheticTake {
    static let duration: Double = 6
    static let framesPerSecond = 30
    static let silentGaps: [EditorTimeRange] = [.init(start: 1.4, end: 2.6), .init(start: 3.6, end: 4.8)]
    static let unspokenSound = EditorTimeRange(start: 2.6, end: 3.6)

    let root: URL
    let settings: RecordingSettings
    let take: RecordingTake

    init() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SyntheticTake-\(UUID().uuidString)")
        var settings = RecordingSettings()
        settings.outputDirectory = root
        settings.enabledSources = [.screen, .camera, .microphone]
        settings.savesSourceFiles = true
        settings.layout = .vertical
        settings.outputResolution = .p1080
        settings.framesPerSecond = Self.framesPerSecond
        self.settings = settings
        let store = TakeFileStore()
        take = try store.createTake(settings: settings)
        try await Self.writeVideo(.init(url: take.screenURL, hue: 0))
        try await Self.writeVideo(.init(url: take.cameraURL, hue: 0.5))
        try Self.writeSpeech(take.audioURL)
        // Rewrite the project now that the media exists, the same way a finished recording does.
        try store.writeRecordingProject(for: take, settings: settings,
            sceneEvents: [RecordingSceneEvent(time: 0, scene: RecordingScene(settings: settings))], finalVideoURL: nil)
        let project = try store.loadRecordingProject(at: take.projectURL)
        try TranscriptArtifactStore().save(.init(transcript: Self.transcript(mediaPath: take.audioURL.path),
            locations: TranscriptArtifactStore().locations(for: project)))
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    private struct VideoRequest {
        let url: URL
        let hue: CGFloat
    }

    /// 1280x720 H.264 with a moving square over a shifting background, so every frame differs.
    private static func writeVideo(_ request: VideoRequest) async throws {
        let width = 1280, height = 720
        let writer = try AVAssetWriter(outputURL: request.url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? RecorderError.writerNotReady }
        writer.startSession(atSourceTime: .zero)
        let frames = Int(duration) * framesPerSecond
        let deadline = ProcessInfo.processInfo.systemUptime + 30
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing, ProcessInfo.processInfo.systemUptime < deadline else {
                    writer.cancelWriting()
                    throw writer.error ?? RecorderError.writerNotReady
                }
                try await Task.sleep(for: .milliseconds(1))
            }
            let pool = try XCTUnwrap(adaptor.pixelBufferPool)
            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else {
                throw RecorderError.writerNotReady
            }
            draw(.init(buffer: buffer, progress: CGFloat(frame) / CGFloat(frames), hue: request.hue))
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: CMTimeScale(framesPerSecond))) else {
                throw writer.error ?? RecorderError.writerNotReady
            }
        }
        writer.endSession(atSourceTime: CMTime(value: Int64(frames), timescale: CMTimeScale(framesPerSecond)))
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? RecorderError.writerNotReady }
    }

    private struct FrameDrawing {
        let buffer: CVPixelBuffer
        let progress: CGFloat
        let hue: CGFloat
    }

    private static func draw(_ request: FrameDrawing) {
        let buffer = request.buffer
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
        let hue = (request.hue + request.progress * 0.3).truncatingRemainder(dividingBy: 1)
        context.setFillColor(CGColor(red: hue, green: 0.4, blue: 1 - hue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let side = CGFloat(height) / 3
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: request.progress * (CGFloat(width) - side), y: (CGFloat(height) - side) / 2,
                            width: side, height: side))
    }

    /// Mono AAC: a 440 Hz tone everywhere except the silent gaps.
    private static func writeSpeech(_ url: URL) throws {
        let sampleRate = 48_000.0
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000
        ])
        let count = AVAudioFrameCount(duration * sampleRate)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count))
        buffer.frameLength = count
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<Int(count) {
            let time = Double(index) / sampleRate
            let silent = silentGaps.contains { time >= $0.start && time < $0.end }
            samples[index] = silent ? 0 : Float(sin(time * 440 * 2 * .pi) * 0.3)
        }
        try file.write(from: buffer)
    }

    private static func transcript(mediaPath: String) -> RecordingTranscript {
        let words: [TranscriptWord] = [
            .init(text: "Hello", startTime: 0.2, endTime: 1.2, confidence: 1),
            .init(text: "again", startTime: 5, endTime: 5.8, confidence: 1)
        ]
        return RecordingTranscriptAssembler.assemble(.init(
            mediaPath: mediaPath, generatedAt: .distantPast, duration: duration,
            confidence: 1, text: words.map(\.text).joined(separator: " "), suggestedTitle: nil, words: words,
            diarizedIntervals: words.map { .init(speakerID: RecordingTranscriptAssembler.microphoneSpeakerID,
                                                 startTime: $0.startTime, endTime: $0.endTime) }))
    }
}

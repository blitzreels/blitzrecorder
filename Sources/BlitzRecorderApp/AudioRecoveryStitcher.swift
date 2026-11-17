import AVFoundation
import Foundation

/// Joins the finished segments of one audio source into a single file, each segment placed by its time on the
/// take timeline, so the file follows the session clock: real gaps become silence, and a source clock that runs a
/// little fast or slow is absorbed by stretching each segment to end where the next one starts, instead of
/// building up until a join has to insert or cut a few milliseconds.
enum AudioRecoveryStitcher {
    struct Request {
        let directory: URL
        let outputURL: URL
        let format: SourceAudioFormat
        let stereoBitrate: Int
        /// Take-timeline second the output starts at; nil starts it at the first segment.
        let timelineStart: Double?
    }

    struct Result: Equatable {
        let timelineStart: Double
        let timelineEnd: Double
        let silenceSeconds: Double
        let unreadableSegments: Int
    }

    private static let toleranceSeconds = 0.02
    /// Largest stretch that is still clock drift: 0.5 %, fifty times what a microphone clock is off. Anything
    /// larger between two segments is a real gap or overlap.
    static let maximumStretch = 0.005
    private static let silenceChunkFrames: AVAudioFrameCount = 48_000

    private final class Output {
        let file: AVAudioFile
        let timelineStart: Double
        var frames: AVAudioFramePosition = 0
        var silenceFrames: AVAudioFramePosition = 0

        var format: AVAudioFormat { file.processingFormat }

        init(file: AVAudioFile, timelineStart: Double) {
            self.file = file
            self.timelineStart = timelineStart
        }
    }

    /// Returns nil when no finished segment could be read.
    static func stitch(_ request: Request) throws -> Result? {
        var output: Output?
        var unreadable = 0
        defer { output?.file.close() }
        let segments = AudioRecoverySegment.finished(in: request.directory)
        for (index, segment) in segments.enumerated() {
            guard var buffer = readableBuffer(segment.url) else {
                unreadable += 1
                continue
            }
            if index + 1 < segments.count {
                buffer = stretched(.init(buffer: buffer, seconds: segments[index + 1].timelineSeconds - segment.timelineSeconds))
            }
            let target = try output ?? makeOutput(.init(request: request, first: buffer, timelineStart: request.timelineStart ?? segment.timelineSeconds))
            output = target
            try append(.init(buffer: buffer, timelineSeconds: segment.timelineSeconds, output: target))
        }
        guard let output else { return nil }
        let rate = output.format.sampleRate
        return Result(
            timelineStart: output.timelineStart,
            timelineEnd: output.timelineStart + Double(output.frames) / rate,
            silenceSeconds: Double(output.silenceFrames) / rate,
            unreadableSegments: unreadable
        )
    }

    struct StretchRequest {
        let buffer: AVAudioPCMBuffer
        /// Seconds until the next segment starts.
        let seconds: Double
    }

    /// The segment resampled to last `seconds`, when that differs from its length by clock drift alone; otherwise
    /// the segment as it is. Four-point Hermite interpolation keeps the top end of a voice, and the last frame
    /// leads straight into the next segment.
    static func stretched(_ request: StretchRequest) -> AVAudioPCMBuffer {
        let buffer = request.buffer
        let source = Int(buffer.frameLength)
        let target = Int((request.seconds * buffer.format.sampleRate).rounded())
        let difference = abs(target - source)
        guard source > 3, difference > 0, Double(difference) <= Double(source) * maximumStretch,
              let input = buffer.floatChannelData,
              let output = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(target)),
              let samples = output.floatChannelData else { return buffer }
        output.frameLength = AVAudioFrameCount(target)
        let step = Double(source) / Double(target)
        for channel in 0..<Int(buffer.format.channelCount) {
            let x = input[channel]
            let y = samples[channel]
            for frame in 0..<target {
                let position = Double(frame) * step
                let i = Int(position)
                let t = Float(position - Double(i))
                let p0 = x[max(i - 1, 0)], p1 = x[i], p2 = x[min(i + 1, source - 1)], p3 = x[min(i + 2, source - 1)]
                let c1 = 0.5 * (p2 - p0)
                let c2 = p0 - 2.5 * p1 + 2 * p2 - 0.5 * p3
                let c3 = 0.5 * (p3 - p0) + 1.5 * (p1 - p2)
                y[frame] = ((c3 * t + c2) * t + c1) * t + p1
            }
        }
        return output
    }

    private static func readableBuffer(_ url: URL) -> AVAudioPCMBuffer? {
        (try? AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false))?.readAllFrames()
    }

    private struct OutputRequest {
        let request: Request
        let first: AVAudioPCMBuffer
        let timelineStart: Double
    }

    private static func makeOutput(_ output: OutputRequest) throws -> Output {
        let settings = output.request.format.outputSettings(.init(
            sampleRate: output.first.format.sampleRate,
            channelCount: max(1, min(2, Int(output.first.format.channelCount))),
            stereoBitrate: output.request.stereoBitrate
        ))
        let file = try AVAudioFile(forWriting: output.request.outputURL, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        return Output(file: file, timelineStart: output.timelineStart)
    }

    private struct AppendRequest {
        let buffer: AVAudioPCMBuffer
        let timelineSeconds: Double
        let output: Output
    }

    private static func append(_ request: AppendRequest) throws {
        let output = request.output
        let rate = output.format.sampleRate
        let targetFrame = AVAudioFramePosition(((request.timelineSeconds - output.timelineStart) * rate).rounded())
        let offset = targetFrame - output.frames
        let tolerance = AVAudioFramePosition(toleranceSeconds * rate)
        if offset > tolerance {
            try writeSilence(.init(frames: offset, output: output))
        }
        let buffer = try converted(.init(buffer: request.buffer, format: output.format))
        let overlap = offset < -tolerance ? AVAudioFrameCount(min(-offset, AVAudioFramePosition(buffer.frameLength))) : 0
        guard overlap < buffer.frameLength else { return }
        if overlap > 0 {
            for channel in 0..<Int(buffer.format.channelCount) {
                guard let samples = buffer.floatChannelData?[channel] else { continue }
                samples.update(from: samples.advanced(by: Int(overlap)), count: Int(buffer.frameLength - overlap))
            }
            buffer.frameLength -= overlap
        }
        try output.file.write(from: buffer)
        output.frames += AVAudioFramePosition(buffer.frameLength)
    }

    private struct SilenceRequest {
        let frames: AVAudioFramePosition
        let output: Output
    }

    private static func writeSilence(_ request: SilenceRequest) throws {
        let output = request.output
        guard let chunk = AVAudioPCMBuffer(pcmFormat: output.format, frameCapacity: silenceChunkFrames) else {
            throw RecorderError.mediaWriteFailed("Could not prepare silence for a gap in the recovered audio.")
        }
        for channel in 0..<Int(output.format.channelCount) {
            chunk.floatChannelData?[channel].update(repeating: 0, count: Int(silenceChunkFrames))
        }
        var remaining = request.frames
        while remaining > 0 {
            chunk.frameLength = AVAudioFrameCount(min(remaining, AVAudioFramePosition(silenceChunkFrames)))
            try output.file.write(from: chunk)
            remaining -= AVAudioFramePosition(chunk.frameLength)
        }
        output.frames += request.frames
        output.silenceFrames += request.frames
    }

    private struct ConversionRequest {
        let buffer: AVAudioPCMBuffer
        let format: AVAudioFormat
    }

    private static func converted(_ request: ConversionRequest) throws -> AVAudioPCMBuffer {
        guard request.buffer.format != request.format else { return request.buffer }
        let ratio = request.format.sampleRate / request.buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(request.buffer.frameLength) * ratio).rounded(.up)) + 1_024
        guard let converter = AVAudioConverter(from: request.buffer.format, to: request.format),
              let output = AVAudioPCMBuffer(pcmFormat: request.format, frameCapacity: capacity) else {
            throw RecorderError.mediaWriteFailed("A recovered audio segment has a format that cannot be converted.")
        }
        converter.downmix = true
        var delivered = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            guard !delivered else {
                inputStatus.pointee = .endOfStream
                return nil
            }
            delivered = true
            inputStatus.pointee = .haveData
            return request.buffer
        }
        if status == .error {
            throw conversionError ?? RecorderError.mediaWriteFailed("A recovered audio segment could not be converted.")
        }
        return output
    }
}

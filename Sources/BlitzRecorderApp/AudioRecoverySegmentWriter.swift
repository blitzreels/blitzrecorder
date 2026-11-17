import AVFoundation
import CoreMedia
import Foundation

struct AudioRecoverySegment: Equatable {
    let url: URL
    let index: Int
    let timelineSeconds: Double

    private static let fileExtension = "caf"

    var unfinishedURL: URL {
        url.deletingPathExtension().appendingPathExtension("part").appendingPathExtension(Self.fileExtension)
    }

    static func fileName(index: Int, timelineSeconds: Double) -> String {
        String(format: "%06d-%013lld.%@", index, Int64((max(0, timelineSeconds) * 1_000_000).rounded()), fileExtension)
    }

    init(url: URL, index: Int, timelineSeconds: Double) {
        self.url = url
        self.index = index
        self.timelineSeconds = timelineSeconds
    }

    init?(url: URL) {
        guard url.pathExtension == Self.fileExtension else { return nil }
        let parts = url.deletingPathExtension().lastPathComponent.split(separator: "-")
        guard parts.count == 2, let index = Int(parts[0]), let micros = Int64(parts[1]) else { return nil }
        self.init(url: url, index: index, timelineSeconds: Double(micros) / 1_000_000)
    }

    /// Finished segments in recording order. A file still marked unfinished was being written when the app stopped.
    static func finished(in directory: URL) -> [AudioRecoverySegment] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap(AudioRecoverySegment.init(url:)).sorted { $0.index < $1.index }
    }
}

/// Keeps a crash-safe copy of one audio source while it records: a new file every few seconds, each one closed,
/// flushed to the disk and only then given its final name. It runs beside the take's own audio file and a failure
/// here never affects the recording.
final class AudioRecoverySegmentWriter: @unchecked Sendable {
    static let segmentSeconds = 5.0
    private static let failureRetrySeconds = 1.0

    struct Request {
        let audioURL: URL
        let timelineStartTime: CMTime?
    }

    /// How much of the source the backup missed through its own fault. Only a backup that missed nothing may
    /// replace the take's audio file; holes in it are then the source's own.
    struct Report: Equatable {
        var lostChunks = 0
        var lostSeconds = 0.0

        var isComplete: Bool { lostChunks == 0 }
    }

    private struct OpenSegment {
        let partURL: URL
        let finalURL: URL
        let file: AVAudioFile
        let format: AVAudioFormat
        let timelineSeconds: Double
        var frames: AVAudioFrameCount

        var expectedNextSeconds: Double { timelineSeconds + Double(frames) / format.sampleRate }
    }

    private struct Chunk {
        let buffer: AVAudioPCMBuffer
        let time: CMTime
    }

    private let directory: URL
    private let timelineStartTime: CMTime?
    private let queue = DispatchQueue(label: "blitzrecorder.audio-recovery-segments", qos: .utility)
    private var origin: CMTime?
    private var pauseClock = MediaWriterPauseClock()
    /// Seconds added to every timestamp so a resumed take continues where the paused one ended, as the file
    /// output does; only a hole while recording shows up between segments.
    private var resumeCorrection = 0.0
    private var isResuming = false
    private var segment: OpenSegment?
    private var nextIndex = 1
    private var retryAt = 0.0
    private var finished = false
    private var hasLoggedFailure = false
    private var report = Report()

    init(_ request: Request) {
        directory = TakeRecoveryFiles.audioSegments(audioURL: request.audioURL)
        timelineStartTime = request.timelineStartTime
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard time.isNumeric, let buffer = Self.pcmBuffer(from: sampleBuffer) else {
            let seconds = CMSampleBufferGetDuration(sampleBuffer).seconds
            queue.async {
                guard !self.finished, !self.pauseClock.isPaused else { return }
                self.noteLost(seconds: seconds.isFinite ? seconds : 0)
            }
            return
        }
        queue.async { self.write(Chunk(buffer: buffer, time: time)) }
    }

    func pause() {
        let hostTime = CMClockGetTime(CMClockGetHostTimeClock())
        queue.async { self.pauseClock.pause(at: hostTime) }
    }

    func resume() {
        let hostTime = CMClockGetTime(CMClockGetHostTimeClock())
        queue.async {
            self.pauseClock.resume(at: hostTime)
            self.isResuming = true
        }
    }

    @discardableResult
    func finish() async -> Report {
        await withCheckedContinuation { (continuation: CheckedContinuation<Report, Never>) in
            queue.async {
                self.finished = true
                self.publishSegment()
                continuation.resume(returning: self.report)
            }
        }
    }

    private func noteLost(seconds: Double) {
        report.lostChunks += 1
        report.lostSeconds += seconds
    }

    private func write(_ chunk: Chunk) {
        guard !finished, !pauseClock.isPaused else { return }
        let origin = origin ?? VideoFileWriter.recordingBaseline(
            timelineStartTime: timelineStartTime, firstSampleTime: chunk.time
        )
        self.origin = origin
        var seconds = max(0, CMTimeSubtract(CMTimeSubtract(chunk.time, origin), pauseClock.offset).seconds)
            + resumeCorrection
        guard seconds.isFinite else { return }
        if isResuming {
            isResuming = false
            if let open = segment {
                resumeCorrection += open.expectedNextSeconds - seconds
                seconds = open.expectedNextSeconds
            }
        }
        if let open = segment,
           open.format != chunk.buffer.format
            || Double(open.frames) / open.format.sampleRate >= Self.segmentSeconds
            || abs(seconds - open.expectedNextSeconds) > AudioSampleContinuity.toleratedJumpSeconds {
            publishSegment()
        }
        LiveAudioTap.shared.publish(.init(buffer: chunk.buffer, seconds: seconds), to: directory)
        do {
            if segment == nil {
                guard seconds >= retryAt else {
                    noteLost(seconds: Double(chunk.buffer.frameLength) / chunk.buffer.format.sampleRate)
                    return
                }
                segment = try openSegment(.init(timelineSeconds: seconds, format: chunk.buffer.format))
            }
            try segment?.file.write(from: chunk.buffer)
            segment?.frames += chunk.buffer.frameLength
        } catch {
            let abandoned = segment.map { Double($0.frames) / $0.format.sampleRate } ?? 0
            abandonSegment()
            noteLost(seconds: abandoned + Double(chunk.buffer.frameLength) / chunk.buffer.format.sampleRate)
            noteFailure(.init(error: error, timelineSeconds: seconds))
        }
    }

    private struct OpenRequest {
        let timelineSeconds: Double
        let format: AVAudioFormat
    }

    private func openSegment(_ request: OpenRequest) throws -> OpenSegment {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let finalURL = directory.appendingPathComponent(
            AudioRecoverySegment.fileName(index: nextIndex, timelineSeconds: request.timelineSeconds)
        )
        let partURL = AudioRecoverySegment(url: finalURL, index: nextIndex, timelineSeconds: request.timelineSeconds).unfinishedURL
        let file = try AVAudioFile(forWriting: partURL, settings: request.format.settings,
                                   commonFormat: request.format.commonFormat, interleaved: request.format.isInterleaved)
        nextIndex += 1
        return OpenSegment(partURL: partURL, finalURL: finalURL, file: file, format: request.format,
                           timelineSeconds: request.timelineSeconds, frames: 0)
    }

    private func publishSegment() {
        guard let open = segment else { return }
        segment = nil
        open.file.close()
        guard open.frames > 0 else {
            try? FileManager.default.removeItem(at: open.partURL)
            return
        }
        DurableFile.flush(open.partURL)
        do {
            try FileManager.default.moveItem(at: open.partURL, to: open.finalURL)
            DurableFile.flush(directory)
        } catch {
            try? FileManager.default.removeItem(at: open.partURL)
            noteLost(seconds: Double(open.frames) / open.format.sampleRate)
            noteFailure(.init(error: error, timelineSeconds: retryAt))
        }
    }

    private func abandonSegment() {
        guard let open = segment else { return }
        segment = nil
        open.file.close()
        try? FileManager.default.removeItem(at: open.partURL)
    }

    private struct Failure {
        let error: Error
        let timelineSeconds: Double
    }

    private func noteFailure(_ failure: Failure) {
        retryAt = failure.timelineSeconds + Self.failureRetrySeconds
        guard !hasLoggedFailure else { return }
        hasLoggedFailure = true
        NSLog("Audio recovery segment failed: %@", failure.error.localizedDescription)
    }

    private static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard CMSampleBufferDataIsReady(sampleBuffer), frameCount > 0,
              let description = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        guard format.commonFormat != .otherFormat,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frameCount), into: buffer.mutableAudioBufferList
        )
        return status == noErr ? buffer : nil
    }
}

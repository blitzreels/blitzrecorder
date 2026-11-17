import AVFoundation
import CoreMedia
import Foundation
import os

private let audioWriterLog = Logger(subsystem: "dev.blitzreels.blitzrecorder", category: "audio-writer")

final class AudioSampleFileWriter: @unchecked Sendable {
    private let url: URL
    private let queue = DispatchQueue(label: "blitzrecorder.audio-writer")
    private let stereoBitrate: Int
    private let format: SourceAudioFormat

    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var paused = false
    private let finalization = MediaWriterFinalization()
    private var finished = false
    private var wroteSample = false
    private var writeError: Error?
    private var didNotifyFirstSample = false
    private var backlog = PendingAudioBacklog()
    var onFirstSampleWritten: (() -> Void)?
    var onFailure: ((Error) -> Void)?

    init(
        url: URL,
        timelineStartTime: CMTime? = nil,
        stereoBitrate: Int = 192_000,
        format: SourceAudioFormat = .aac
    ) throws {
        self.url = url
        self.stereoBitrate = stereoBitrate
        self.format = format
        try? FileManager.default.removeItem(at: url)
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        queue.async {
            guard !self.finished, CMSampleBufferDataIsReady(sampleBuffer) else { return }

            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard presentationTime.isValid else { return }

            if self.writer == nil {
                do {
                    try self.prepareWriter(for: sampleBuffer)
                } catch {
                    self.failWriting(error)
                    return
                }
            }

            guard !self.paused, let input = self.input else { return }
            self.backlog.add(sampleBuffer)
            self.noteWritten(self.backlog.drain(into: input))
        }
    }

    private func noteWritten(_ result: PendingAudioBacklog.DrainResult) {
        if result.appended > 0 {
            wroteSample = true
            if !didNotifyFirstSample {
                didNotifyFirstSample = true
                onFirstSampleWritten?()
            }
        }
        if result.rejected {
            failWriting(writer?.error ?? RecorderError.mediaWriteFailed("Audio writer rejected a sample."))
        }
    }

    private func flushBacklog() {
        guard let input else { return }
        noteWritten(backlog.flush(into: input))
        if backlog.droppedCount > 0 {
            audioWriterLog.error(
                "Dropped \(self.backlog.droppedCount, privacy: .public) audio buffers for \(self.url.lastPathComponent, privacy: .public)"
            )
        }
    }

    func pause() {
        queue.async {
            guard !self.paused else { return }
            self.paused = true
            CaptureLog.note("\(self.url.lastPathComponent): paused")
        }
    }

    func resume() {
        queue.async {
            guard self.paused else { return }
            self.paused = false
            CaptureLog.note("\(self.url.lastPathComponent): resumed")
        }
    }

    func finish() async throws -> MediaWriterCompletion {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.finalization.begin(continuation) else { return }
                if self.writeError == nil { self.flushBacklog() }
                self.finished = true
                if let writeError = self.writeError {
                    try? FileManager.default.removeItem(at: self.url)
                    self.finalization.complete(.failure(writeError))
                    return
                }
                guard self.wroteSample else {
                    self.writer?.cancelWriting()
                    try? FileManager.default.removeItem(at: self.url)
                    self.finalization.complete(.success(.empty(self.url)))
                    return
                }
                guard let writer = self.writer, let input = self.input else {
                    self.finalization.complete(.success(.empty(self.url)))
                    return
                }
                input.markAsFinished()
                writer.finishWriting {
                    self.queue.async {
                        guard writer.status == .completed else {
                            try? FileManager.default.removeItem(at: self.url)
                            self.finalization.complete(.failure(writer.error ?? RecorderError.writerNotReady))
                            return
                        }
                        self.finalization.complete(.success(.wrote(self.url)))
                    }
                }
            }
        }
    }

    private func prepareWriter(for sampleBuffer: CMSampleBuffer) throws {
        guard writer == nil, input == nil else { return }

        let writer = try AVAssetWriter(outputURL: url, fileType: format.avFileType)
        let outputSettings = outputSettings(for: sampleBuffer)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = true

        guard writer.canAdd(input) else {
            throw RecorderError.writerNotReady
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? RecorderError.writerNotReady
        }
        writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        self.writer = writer
        self.input = input
    }

    private func outputSettings(for sampleBuffer: CMSampleBuffer) -> [String: Any] {
        let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)
        let streamDescription = formatDescription.flatMap {
            CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee
        }
        let sampleRate = streamDescription?.mSampleRate ?? 48_000
        let channelCount = max(1, min(2, Int(streamDescription?.mChannelsPerFrame ?? 2)))
        return format.outputSettings(.init(sampleRate: sampleRate, channelCount: channelCount, stereoBitrate: stereoBitrate))
    }

    private func failWriting(_ error: Error) {
        guard writeError == nil else { return }
        writeError = error
        finished = true
        writer?.cancelWriting()
        try? FileManager.default.removeItem(at: url)
        onFailure?(error)
    }
}

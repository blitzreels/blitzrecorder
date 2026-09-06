import AVFoundation
import CoreMedia
import Foundation

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

            guard !self.paused,
                  let input = self.input,
                  input.isReadyForMoreMediaData else {
                return
            }

            if input.append(sampleBuffer) {
                self.wroteSample = true
                if !self.didNotifyFirstSample {
                    self.didNotifyFirstSample = true
                    self.onFirstSampleWritten?()
                }
            } else {
                self.failWriting(
                    self.writer?.error ?? RecorderError.mediaWriteFailed("Audio writer rejected a sample.")
                )
            }
        }
    }

    func pause() {
        queue.async {
            guard !self.paused else { return }
            self.paused = true
        }
    }

    func resume() {
        queue.async {
            guard self.paused else { return }
            self.paused = false
        }
    }

    func finish() async throws -> MediaWriterCompletion {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.finalization.begin(continuation) else { return }
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
        if format.isLossless {
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channelCount,
                AVLinearPCMBitDepthKey: 24,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        }
        return [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVEncoderBitRateKey: channelCount == 1 ? stereoBitrate / 2 : stereoBitrate
        ]
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

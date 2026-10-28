import Accelerate
import AVFoundation
import CoreMedia
import Foundation

/// Mixes several microphone files into one track. Each file is placed by its start on the take timeline, so the
/// mix starts at the earliest one. Sample rates and channel counts may differ; the mix is 48 kHz, stereo when any
/// input is stereo, with a soft limiter so voices summed together never clip.
enum MicrophoneMixdown {
    struct Input {
        let url: URL
        let timelineOffset: CMTime
    }

    struct Request {
        let inputs: [Input]
        let outputURL: URL
        let format: SourceAudioFormat
        let bitrate: Int
        let onProgress: @Sendable (Double) -> Void
    }

    private static let sampleRate = 48_000.0

    /// Returns where the mix starts on the take timeline.
    static func mix(_ request: Request) async throws -> CMTime {
        let delays = await MicrophoneAlignment.soundDelays(request.inputs)
        let placements = zip(request.inputs, delays).map { CMTimeSubtract($0.timelineOffset, $1) }
        // A mic moved earlier than the take's start loses that lead-in: it is sound from before the take began.
        let start = CMTimeMaximum(.zero, placements.min { CMTimeCompare($0, $1) < 0 } ?? .zero)
        let composition = AVMutableComposition()
        var channelCount = 1
        var duration = CMTime.zero
        for (input, inputPlacement) in zip(request.inputs, placements) {
            let asset = AVURLAsset(url: input.url)
            guard let track = try await asset.loadTracks(withMediaType: .audio).first,
                  let compositionTrack = composition.addMutableTrack(
                      withMediaType: .audio,
                      preferredTrackID: kCMPersistentTrackID_Invalid
                  ) else { continue }
            var timeRange = try await track.load(.timeRange)
            var placement = CMTimeSubtract(inputPlacement, start)
            if CMTimeCompare(placement, .zero) < 0 {
                let skipped = CMTimeMultiply(placement, multiplier: -1)
                timeRange = CMTimeRange(start: CMTimeAdd(timeRange.start, skipped),
                                        duration: CMTimeSubtract(timeRange.duration, skipped))
                placement = .zero
            }
            guard CMTimeCompare(timeRange.duration, .zero) > 0 else { continue }
            try compositionTrack.insertTimeRange(timeRange, of: track, at: placement)
            duration = CMTimeMaximum(duration, CMTimeAdd(placement, timeRange.duration))
            let channels = try await track.load(.formatDescriptions).first?.audioStreamBasicDescription?.mChannelsPerFrame
            channelCount = max(channelCount, min(2, Int(channels ?? 1)))
        }
        guard composition.tracks(withMediaType: .audio).count >= 2, CMTimeCompare(duration, .zero) > 0 else {
            throw RecorderError.mediaWriteFailed("Fewer than two microphones have readable audio.")
        }

        let temporaryURL = request.outputURL.deletingLastPathComponent().appendingPathComponent(
            ".\(request.outputURL.deletingPathExtension().lastPathComponent)-mix-\(UUID().uuidString).\(request.format.fileExtension)"
        )
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try await render(.init(
            composition: composition,
            outputURL: temporaryURL,
            format: request.format,
            bitrate: request.bitrate,
            channelCount: channelCount,
            duration: duration,
            onProgress: request.onProgress
        ))
        try replace(request.outputURL, with: temporaryURL)
        request.onProgress(1)
        return start
    }

    /// Puts one microphone's file in place of the mix when only one microphone recorded.
    static func copy(_ url: URL, to outputURL: URL) throws {
        guard url != outputURL else { return }
        let temporaryURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).\(outputURL.pathExtension)")
        try FileManager.default.copyItem(at: url, to: temporaryURL)
        try replace(outputURL, with: temporaryURL)
    }

    private static func replace(_ url: URL, with temporaryURL: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: url)
        }
    }

    private struct RenderRequest {
        let composition: AVMutableComposition
        let outputURL: URL
        let format: SourceAudioFormat
        let bitrate: Int
        let channelCount: Int
        let duration: CMTime
        let onProgress: @Sendable (Double) -> Void
    }

    private static func render(_ request: RenderRequest) async throws {
        let reader = try AVAssetReader(asset: request.composition)
        let output = AVAssetReaderAudioMixOutput(
            audioTracks: request.composition.tracks(withMediaType: .audio),
            audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: request.channelCount,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        )
        guard reader.canAdd(output) else { throw RecorderError.exportUnavailable }
        reader.add(output)

        let writer = try AVAssetWriter(outputURL: request.outputURL, fileType: request.format.avFileType)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings(request))
        guard writer.canAdd(input) else { throw RecorderError.writerNotReady }
        writer.add(input)
        guard writer.startWriting(), reader.startReading() else {
            throw writer.error ?? reader.error ?? RecorderError.writerNotReady
        }
        writer.startSession(atSourceTime: .zero)
        try await pump(.init(reader: reader, output: output, writer: writer, input: input,
                             duration: request.duration, onProgress: request.onProgress))
    }

    private static func outputSettings(_ request: RenderRequest) -> [String: Any] {
        if request.format.isLossless {
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: request.channelCount,
                AVLinearPCMBitDepthKey: 24,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        }
        return [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: request.channelCount,
            AVEncoderBitRateKey: request.channelCount == 1 ? request.bitrate / 2 : request.bitrate
        ]
    }

    private struct PumpRequest: @unchecked Sendable {
        let reader: AVAssetReader
        let output: AVAssetReaderOutput
        let writer: AVAssetWriter
        let input: AVAssetWriterInput
        let duration: CMTime
        let onProgress: @Sendable (Double) -> Void
    }

    private static func pump(_ request: PumpRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            request.input.requestMediaDataWhenReady(on: DispatchQueue(label: "blitzrecorder.microphone-mixdown")) {
                while request.input.isReadyForMoreMediaData {
                    guard let sampleBuffer = request.output.copyNextSampleBuffer() else {
                        request.input.markAsFinished()
                        if request.reader.status == .failed {
                            request.writer.cancelWriting()
                            continuation.resume(throwing: request.reader.error ?? RecorderError.exportUnavailable)
                            return
                        }
                        request.writer.finishWriting {
                            if request.writer.status == .completed {
                                continuation.resume()
                            } else {
                                continuation.resume(throwing: request.writer.error ?? RecorderError.writerNotReady)
                            }
                        }
                        return
                    }
                    SoftLimiter.apply(to: sampleBuffer)
                    guard request.input.append(sampleBuffer) else {
                        request.reader.cancelReading()
                        request.writer.cancelWriting()
                        continuation.resume(throwing: request.writer.error
                            ?? RecorderError.mediaWriteFailed("The microphone mix writer rejected an audio sample."))
                        return
                    }
                    let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
                    if time.isFinite, request.duration.seconds > 0 {
                        request.onProgress(min(0.99, max(0, time / request.duration.seconds)))
                    }
                }
            }
        }
    }
}

/// Leaves samples below the knee untouched and bends louder ones smoothly toward full scale.
private enum SoftLimiter {
    private static let knee: Float = 0.9

    static func apply(to sampleBuffer: CMSampleBuffer) {
        var blockBuffer: CMBlockBuffer?
        var bufferList = AudioBufferList()
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &bufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        ) == noErr else { return }
        for buffer in UnsafeMutableAudioBufferListPointer(&bufferList) {
            guard let data = buffer.mData else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)
            for index in 0..<(Int(buffer.mDataByteSize) / MemoryLayout<Float>.size) {
                let sample = samples[index]
                let magnitude = abs(sample)
                guard magnitude > knee else { continue }
                let limited = knee + (1 - knee) * tanh((magnitude - knee) / (1 - knee))
                samples[index] = sample < 0 ? -limited : limited
            }
        }
    }
}

/// Lines microphones up by their sound. Each device holds its audio for a while before the Mac sees it (USB camera
/// mics like an Osmo hold several hundred milliseconds) and macOS only subtracts the delay a device reports, so
/// first-sample timestamps can leave two mics of the same voice audibly apart. Speech loudness is compared at 1 ms
/// steps; a mic is moved only when the match is clear.
enum MicrophoneAlignment {
    private static let envelopeRate = 1_000.0
    private static let readRate = 16_000.0
    private static let maximumLagMilliseconds = 1_500
    private static let minimumMatch: Float = 0.3
    /// Five minutes of speech is plenty to find a fixed delay and keeps hour-long takes quick.
    private static let maximumMeasuredMilliseconds = 300_000

    /// How much later each input's sound arrives than the earliest microphone's. Zero when unmeasurable.
    static func soundDelays(_ inputs: [MicrophoneMixdown.Input]) async -> [CMTime] {
        guard inputs.count >= 2 else { return inputs.map { _ in .zero } }
        var envelopes: [[Float]] = []
        for input in inputs {
            guard let envelope = await envelope(input) else { return inputs.map { _ in .zero } }
            envelopes.append(envelope)
        }
        var lags: [Int?] = [0]
        for index in envelopes.indices.dropFirst() {
            lags.append(lagMilliseconds(reference: envelopes[0], other: envelopes[index]))
        }
        let measured = lags.compactMap { $0 }
        let earliest = measured.min() ?? 0
        let delays = lags.map { lag in
            lag.map { CMTime(value: CMTimeValue($0 - earliest), timescale: 1_000) } ?? .zero
        }
        NSLog("Microphone alignment: lags %@ ms", lags.map { $0.map(String.init) ?? "?" }.joined(separator: ", "))
        return delays
    }

    /// Log speech loudness at 1 ms steps, placed on the take timeline by the input's timestamp.
    private static func envelope(_ input: MicrophoneMixdown.Input) async -> [Float]? {
        let asset = AVURLAsset(url: input.url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: readRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false
        ])
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        let floor: Float = log(1e-4)
        let lead = max(0, Int((input.timelineOffset.seconds * envelopeRate).rounded()))
        var envelope = [Float](repeating: floor, count: lead)
        let window = Int(readRate / envelopeRate)
        var pending: [Float] = []
        while let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
            let length = CMBlockBufferGetDataLength(block)
            var samples = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            samples.withUnsafeMutableBytes { bytes in
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: bytes.baseAddress!)
            }
            pending += samples
            let whole = pending.count / window
            for step in 0..<whole {
                var meanSquare: Float = 0
                pending.withUnsafeBufferPointer { pointer in
                    vDSP_measqv(pointer.baseAddress! + step * window, 1, &meanSquare, vDSP_Length(window))
                }
                envelope.append(log(sqrt(meanSquare) + 1e-4))
            }
            pending.removeFirst(whole * window)
        }
        return reader.status == .completed ? envelope : nil
    }

    /// Milliseconds the other envelope runs behind the reference, or nil without a clear match.
    private static func lagMilliseconds(reference: [Float], other: [Float]) -> Int? {
        let count = min(reference.count, other.count, maximumMeasuredMilliseconds)
        let maximumLag = maximumLagMilliseconds
        guard count > maximumLag * 4 else { return nil }
        let a = centered(Array(reference.prefix(count)))
        let b = centered(Array(other.prefix(count)))
        var best: (lag: Int, score: Float) = (0, -1)
        for lag in -maximumLag...maximumLag {
            let length = count - abs(lag)
            let aStart = lag < 0 ? -lag : 0
            let bStart = lag > 0 ? lag : 0
            var dot: Float = 0, aEnergy: Float = 0, bEnergy: Float = 0
            a.withUnsafeBufferPointer { aPointer in
                b.withUnsafeBufferPointer { bPointer in
                    let x = aPointer.baseAddress! + aStart, y = bPointer.baseAddress! + bStart
                    vDSP_dotpr(x, 1, y, 1, &dot, vDSP_Length(length))
                    vDSP_svesq(x, 1, &aEnergy, vDSP_Length(length))
                    vDSP_svesq(y, 1, &bEnergy, vDSP_Length(length))
                }
            }
            let score = dot / max(sqrt(aEnergy * bEnergy), 1e-9)
            if score > best.score { best = (lag, score) }
        }
        return best.score >= minimumMatch ? best.lag : nil
    }

    private static func centered(_ values: [Float]) -> [Float] {
        var mean: Float = 0
        vDSP_meanv(values, 1, &mean, vDSP_Length(values.count))
        return values.map { $0 - mean }
    }
}

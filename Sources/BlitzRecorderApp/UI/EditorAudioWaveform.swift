import AVFoundation
import Accelerate
import Foundation

final class EditorAudioWaveform: Sendable {
    struct Request {
        let peaks: [Float]
    }

    struct ColumnRequest {
        let index: Int
        let count: Int
    }

    let levels: [[Float]]

    init(_ request: Request) {
        var peaks = request.peaks.map { $0.isFinite ? max(0, $0) : 0 }
        if let maximum = peaks.max(), maximum > 0, maximum != 1 {
            for index in peaks.indices { peaks[index] /= maximum }
        }
        levels = Self.makeLevels(peaks)
    }

    init?(cachedPeaks: [Float]) {
        guard cachedPeaks.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }) else { return nil }
        levels = Self.makeLevels(cachedPeaks)
    }

    private static func makeLevels(_ initial: [Float]) -> [[Float]] {
        var peaks = initial
        var levels = [peaks]
        while peaks.count > 1 {
            var reduced = [Float](repeating: 0, count: (peaks.count + 1) / 2)
            peaks.withUnsafeBufferPointer { source in
                reduced.withUnsafeMutableBufferPointer { destination in
                    vDSP_vmax(source.baseAddress!, 2, source.baseAddress!.advanced(by: 1), 2,
                              destination.baseAddress!, 1, vDSP_Length(peaks.count / 2))
                }
            }
            if !peaks.count.isMultiple(of: 2) { reduced[reduced.count - 1] = peaks[peaks.count - 1] }
            peaks = reduced
            levels.append(peaks)
        }
        return levels
    }

    var overview: [Float] {
        levels.first { $0.count <= 4_096 } ?? []
    }

    func amplitude(_ request: ColumnRequest) -> Float {
        let sampleCount = levels[0].count
        guard sampleCount > 0, request.count > 0, request.index >= 0, request.index < request.count else { return 0 }
        let first = request.index * sampleCount / request.count
        return peak(.init(start: first, end: max(first + 1, (request.index + 1) * sampleCount / request.count)))
    }

    struct RangeRequest {
        let start: Double
        let end: Double
    }

    func amplitude(_ request: RangeRequest) -> Float {
        let count = levels[0].count
        guard count > 0, request.start.isFinite, request.end.isFinite, request.end > request.start else { return 0 }
        let first = Int(floor(min(1, max(0, request.start)) * Double(count)))
        let end = Int(ceil(min(1, max(0, request.end)) * Double(count)))
        return peak(.init(start: first, end: max(first, end)))
    }

    private struct PeakRequest {
        let start: Int
        let end: Int
    }

    private func peak(_ request: PeakRequest) -> Float {
        var first = request.start
        var end = request.end
        var level = 0
        var peak: Float = 0
        while first < end {
            if first % 2 == 1 {
                peak = max(peak, levels[level][first])
                first += 1
            }
            if end % 2 == 1 {
                end -= 1
                peak = max(peak, levels[level][end])
            }
            first /= 2
            end /= 2
            level += 1
        }
        return peak
    }

    struct LoadRequest {
        let asset: AVURLAsset
        let duration: Double
    }

    static func load(_ request: LoadRequest) async -> EditorAudioWaveform? {
        guard !Task.isCancelled, request.duration.isFinite, request.duration > 0 else { return nil }
        let cacheKey = MediaFileFingerprint(url: request.asset.url).map {
            EditorWaveformCache.Key(file: $0, duration: request.duration)
        }
        if let cacheKey, let waveform = await EditorWaveformCache.shared.load(cacheKey) { return waveform }
        guard request.duration.isFinite, request.duration > 0,
            let track = try? await request.asset.loadTracks(withMediaType: .audio).first,
            let reader = try? AVAssetReader(asset: request.asset)
        else { return nil }
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        var accumulator = EditorAudioPeakAccumulator(duration: request.duration)
        var scratch: [Float] = []
        while reader.status == .reading, let buffer = output.copyNextSampleBuffer() {
            if Task.isCancelled {
                reader.cancelReading()
                return nil
            }
            guard let block = CMSampleBufferGetDataBuffer(buffer),
                let format = CMSampleBufferGetFormatDescription(buffer),
                let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
            else { continue }
            let byteCount = CMBlockBufferGetDataLength(block)
            let sampleCount = byteCount / MemoryLayout<Float>.size
            guard sampleCount > 0 else { continue }
            if scratch.count < sampleCount { scratch = [Float](repeating: 0, count: sampleCount) }
            let status = scratch.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: byteCount, destination: $0.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { continue }
            scratch.withUnsafeBufferPointer {
                accumulator.append(
                    .init(
                        samples: UnsafeBufferPointer(start: $0.baseAddress, count: sampleCount),
                        startTime: CMSampleBufferGetPresentationTimeStamp(buffer).seconds,
                        sampleRate: description.mSampleRate,
                        channelCount: Int(description.mChannelsPerFrame)
                    ))
            }
        }
        guard reader.status == .completed, !Task.isCancelled else { return nil }
        let waveform = EditorAudioWaveform(.init(peaks: accumulator.peaks))
        if let cacheKey { await EditorWaveformCache.shared.save(.init(key: cacheKey, waveform: waveform)) }
        return waveform
    }
}

struct EditorAudioPeakAccumulator {
    struct Request {
        let samples: UnsafeBufferPointer<Float>
        let startTime: Double
        let sampleRate: Double
        let channelCount: Int
    }

    let duration: Double
    private(set) var peaks: [Float]

    init(duration: Double) {
        self.duration = duration.isFinite ? max(0, duration) : 0
        peaks = [Float](repeating: 0, count: max(1, Int(min(8_000_000, ceil(self.duration * 1_000)))))
    }

    mutating func append(_ request: Request) {
        guard duration > 0, request.startTime.isFinite,
            request.sampleRate.isFinite, request.sampleRate > 0,
            request.channelCount > 0, let samples = request.samples.baseAddress
        else { return }
        let frameCount = request.samples.count / request.channelCount
        let framesBeforeStart = max(0, ceil(-request.startTime * request.sampleRate))
        var frame = Int(min(Double(frameCount), framesBeforeStart))
        while frame < frameCount {
            let time = request.startTime + Double(frame) / request.sampleRate
            guard time < duration else { break }
            let bucket = min(peaks.count - 1, max(0, Int(floor(time / duration * Double(peaks.count) + 0.000_000_1))))
            let boundary = Double(bucket + 1) * duration / Double(peaks.count)
            let boundaryFrame = ceil((boundary - request.startTime) * request.sampleRate - 0.000_001)
            let end = max(frame + 1, Int(min(Double(frameCount), max(0, boundaryFrame))))
            var peak: Float = 0
            vDSP_maxmgv(
                samples.advanced(by: frame * request.channelCount), 1, &peak,
                vDSP_Length((end - frame) * request.channelCount)
            )
            if peak.isFinite { peaks[bucket] = max(peaks[bucket], peak) }
            frame = end
        }
    }
}

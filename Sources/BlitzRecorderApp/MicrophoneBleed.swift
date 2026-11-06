import Accelerate
import Foundation

enum MicrophoneBleed {
    struct Request {
        let microphone: [Float]
        let system: [Float]
    }

    struct Result {
        let microphone: [Float]
        let systemDelay: TimeInterval?
        let removedSeconds: TimeInterval
    }

    private static let sampleRate = 16_000
    private static let hop = 320
    private static let size = 512
    private static let bandEdges: [Float] = [100, 300, 600, 1_200, 2_400, 4_000, 7_000]
    private static let speechBands = 1..<5
    private static let maximumDelayFrames = 25
    private static let nativeMarginRatio: Float = 6.3
    private static let nativeHangoverFrames = 10
    private static let fadeSamples = 80

    static func removed(_ request: Request) -> Result {
        let unchanged = Result(microphone: request.microphone, systemDelay: nil, removedSeconds: 0)
        let microphone = bandEnergies(request.microphone)
        let system = bandEnergies(request.system)
        let count = min(microphone.count, system.count)
        guard count > 3_000 else { return unchanged }
        let micSpeech = microphone.prefix(count).map { speechEnergy($0) }
        let systemSpeech = system.prefix(count).map { speechEnergy($0) }
        let systemFloor = percentile(.init(values: systemSpeech, fraction: 0.1))
        let active = systemSpeech.map { $0 > systemFloor * 31.6 }
        guard let delay = systemDelay(.init(
            microphone: micSpeech, system: systemSpeech, active: active
        )) else { return unchanged }

        let aligned = (0..<count).map { frame in
            frame + delay < count && frame + delay >= 0 ? system[frame + delay] : [Float](repeating: 0, count: bandEdges.count - 1)
        }
        let alignedActive = (0..<count).map { frame in
            frame + delay < count && frame + delay >= 0 && active[frame + delay]
        }
        let gains = (0..<bandEdges.count - 1).map { band -> Float in
            let loud = (0..<count).filter { alignedActive[$0] }.map { aligned[$0][band] }
            let threshold = percentile(.init(values: loud, fraction: 0.5))
            let ratios = (0..<count).compactMap { frame -> Float? in
                guard alignedActive[frame], aligned[frame][band] > threshold, aligned[frame][band] > 0 else { return nil }
                return microphone[frame][band] / aligned[frame][band]
            }
            return percentile(.init(values: ratios, fraction: 0.3))
        }
        let noise = (0..<bandEdges.count - 1).map { band in
            percentile(.init(values: (0..<count).map { microphone[$0][band] }, fraction: 0.1))
        }
        let native = (0..<count).map { frame -> Bool in
            var predicted: Float = 0
            var heard: Float = 0
            for band in speechBands {
                let echo = (max(0, frame - 1)...min(count - 1, frame + 3)).map { aligned[$0][band] }.max() ?? 0
                predicted += gains[band] * echo + noise[band]
                heard += microphone[frame][band]
            }
            return heard >= predicted * nativeMarginRatio
        }
        var nearNative = [Bool](repeating: false, count: count)
        for frame in 0..<count where native[frame] {
            for neighbor in max(0, frame - nativeHangoverFrames)...min(count - 1, frame + nativeHangoverFrames) {
                nearNative[neighbor] = true
            }
        }
        let bleed = (0..<count).map { alignedActive[$0] && !nearNative[$0] }
        return Result(
            microphone: silenced(.init(samples: request.microphone, frames: bleed)),
            systemDelay: Double(delay * hop) / Double(sampleRate),
            removedSeconds: Double(bleed.filter { $0 }.count * hop) / Double(sampleRate)
        )
    }

    private struct DelayRequest {
        let microphone: [Float]
        let system: [Float]
        let active: [Bool]
    }

    private static func systemDelay(_ request: DelayRequest) -> Int? {
        let count = request.microphone.count
        let quiet = percentile(.init(values: request.microphone, fraction: 0.5))
        let micLog = request.microphone.map { log10($0 + 1e-12) }
        let systemLog = request.system.map { log10($0 + 1e-12) }
        var correlations: [(delay: Int, value: Float)] = []
        for delay in -maximumDelayFrames...maximumDelayFrames {
            var pairs: [(Float, Float)] = []
            for frame in max(0, -delay)..<min(count, count - delay)
            where request.active[frame + delay] && request.microphone[frame] < quiet {
                pairs.append((micLog[frame], systemLog[frame + delay]))
            }
            guard pairs.count >= 500 else { continue }
            correlations.append((delay, pearson(pairs)))
        }
        guard let best = correlations.max(by: { $0.value < $1.value }) else { return nil }
        let median = percentile(.init(values: correlations.map(\.value), fraction: 0.5))
        return best.value >= 0.3 && best.value - median >= 0.2 ? best.delay : nil
    }

    private static func pearson(_ pairs: [(Float, Float)]) -> Float {
        let n = Float(pairs.count)
        let meanX = pairs.reduce(0) { $0 + $1.0 } / n
        let meanY = pairs.reduce(0) { $0 + $1.1 } / n
        var covariance: Float = 0
        var varianceX: Float = 0
        var varianceY: Float = 0
        for (x, y) in pairs {
            covariance += (x - meanX) * (y - meanY)
            varianceX += (x - meanX) * (x - meanX)
            varianceY += (y - meanY) * (y - meanY)
        }
        guard varianceX > 0, varianceY > 0 else { return 0 }
        return covariance / (varianceX.squareRoot() * varianceY.squareRoot())
    }

    private static func speechEnergy(_ bands: [Float]) -> Float {
        speechBands.reduce(0) { $0 + bands[$1] }
    }

    private static func bandEnergies(_ samples: [Float]) -> [[Float]] {
        guard samples.count >= size,
              let transform = vDSP.DFT(count: size, direction: .forward, transformType: .complexComplex,
                                       ofType: Float.self) else { return [] }
        let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: size,
                                 isHalfWindow: false)
        let binWidth = Float(sampleRate) / Float(size)
        let bins = (0..<bandEdges.count - 1).map { band in
            (0...(size / 2)).filter {
                Float($0) * binWidth >= bandEdges[band] && Float($0) * binWidth < bandEdges[band + 1]
            }
        }
        let imaginary = [Float](repeating: 0, count: size)
        var real = [Float](repeating: 0, count: size)
        var outputReal = [Float](repeating: 0, count: size)
        var outputImaginary = [Float](repeating: 0, count: size)
        let frames = (samples.count - size) / hop + 1
        var result: [[Float]] = []
        result.reserveCapacity(frames)
        for frame in 0..<frames {
            let start = frame * hop
            samples.withUnsafeBufferPointer { pointer in
                vDSP.multiply(UnsafeBufferPointer(rebasing: pointer[start..<start + size]), window, result: &real)
            }
            transform.transform(inputReal: real, inputImaginary: imaginary,
                                outputReal: &outputReal, outputImaginary: &outputImaginary)
            result.append(bins.map { band in
                band.reduce(Float(0)) { $0 + outputReal[$1] * outputReal[$1] + outputImaginary[$1] * outputImaginary[$1] }
            })
        }
        return result
    }

    private struct PercentileRequest {
        let values: [Float]
        let fraction: Double
    }

    private static func percentile(_ request: PercentileRequest) -> Float {
        guard !request.values.isEmpty else { return 0 }
        let sorted = request.values.sorted()
        let index = Int((Double(sorted.count - 1) * request.fraction).rounded())
        return sorted[min(sorted.count - 1, max(0, index))]
    }

    private struct SilenceRequest {
        let samples: [Float]
        let frames: [Bool]
    }

    private static func silenced(_ request: SilenceRequest) -> [Float] {
        var samples = request.samples
        let offset = (size - hop) / 2
        var frame = 0
        while frame < request.frames.count {
            guard request.frames[frame] else { frame += 1; continue }
            var end = frame
            while end < request.frames.count, request.frames[end] { end += 1 }
            let first = min(samples.count, frame * hop + offset)
            let last = min(samples.count, end * hop + offset)
            for index in first..<last {
                let fromStart = index - first
                let toEnd = last - 1 - index
                let ramp = min(fromStart, toEnd)
                samples[index] *= ramp >= fadeSamples ? 0 : 1 - Float(ramp) / Float(fadeSamples)
            }
            frame = end
        }
        return samples
    }
}

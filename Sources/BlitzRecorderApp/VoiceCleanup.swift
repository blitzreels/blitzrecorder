import Accelerate
import AVFoundation
import CryptoKit
import Foundation

struct VoiceCleanupSettings: Codable, Equatable, Sendable {
    var isEnabled = false
    var strength = 0.65
    var normalizesSpeech = true
    var ducksMusic = false
    static let disabled = Self()
}

actor VoiceCleanupProcessor {
    static let shared = VoiceCleanupProcessor()

    struct Request {
        let url: URL
        let settings: VoiceCleanupSettings
    }

    func processed(_ request: Request) async throws -> URL {
        guard request.settings.isEnabled else { return request.url }
        guard let fingerprint = MediaFileFingerprint(url: request.url) else {
            throw RecorderError.mediaWriteFailed("The microphone source is unavailable for voice cleanup.")
        }
        let key = fingerprint.cacheKey + "-voice-v1-\(request.settings.strength)-\(request.settings.normalizesSpeech)"
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dev.blitzreels.blitzrecorder/VoiceCleanup", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(name + ".m4a")
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        let scratch = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let pcm = scratch.appendingPathComponent("processed.caf")
        try Self.processPCM(.init(source: request.url, destination: pcm, settings: request.settings))
        try Task.checkCancellation()
        guard let exporter = AVAssetExportSession(asset: AVURLAsset(url: pcm), presetName: AVAssetExportPresetAppleM4A) else {
            throw RecorderError.mediaWriteFailed("Cannot encode cleaned microphone audio.")
        }
        let encoded = scratch.appendingPathComponent("processed.m4a")
        try await exporter.export(to: encoded, as: .m4a)
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        try FileManager.default.moveItem(at: encoded, to: destination)
        return destination
    }

    struct PCMRequest {
        let source: URL
        let destination: URL
        let settings: VoiceCleanupSettings
    }

    static func processPCM(_ request: PCMRequest) throws {
        let file = try AVAudioFile(forReading: request.source, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        let channels = Int(format.channelCount)
        let length = Int(file.length)
        guard channels > 0, length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024) else {
            throw RecorderError.mediaWriteFailed("The microphone source has no readable samples.")
        }
        let fft = try VoiceSpectrum()
        var candidates: [(energy: Float, samples: [Float])] = []
        var loudest: Float = 0
        let analysisLimit = min(length, Int(format.sampleRate * 45))
        while file.framePosition < analysisLimit {
            try Task.checkCancellation()
            try file.read(into: buffer, frameCount: 1024)
            guard buffer.frameLength > 0, let data = buffer.floatChannelData else { break }
            var mono = [Float](repeating: 0, count: 1024)
            for i in 0..<Int(buffer.frameLength) {
                for channel in 0..<channels { mono[i] += data[channel][i] / Float(channels) }
            }
            let energy = sqrt(mono.reduce(0) { $0 + $1 * $1 } / 1024)
            loudest = max(loudest, energy)
            if energy > 0.00001 && (candidates.count < 24 || energy < (candidates.last?.energy ?? 0)) {
                candidates.append((energy, mono))
                candidates.sort { $0.energy < $1.energy }
                if candidates.count > 24 { candidates.removeLast() }
            }
        }
        var noise = [Float](repeating: 0, count: 1024)
        for candidate in candidates {
            let spectrum = fft.forward(candidate.samples)
            for i in 0..<1024 {
                noise[i] += (spectrum.real[i] * spectrum.real[i] + spectrum.imaginary[i] * spectrum.imaginary[i]) / Float(candidates.count)
            }
        }
        let noiseRMS = candidates.first?.energy ?? 0
        if noiseRMS > loudest * 0.7 { noise = noise.map { $0 * 0.25 } }
        file.framePosition = 0
        let output = try AVAudioFile(forWriting: request.destination, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: channels, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512),
              let result = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512) else {
            throw RecorderError.mediaWriteFailed("Cannot allocate voice cleanup buffers.")
        }
        var previous = Array(repeating: [Float](repeating: 0, count: 512), count: channels)
        var overlap = previous
        var first = true
        var written = 0
        var gain: Float = 1
        let strength = Float(min(1, max(0, request.settings.strength)))
        while written < length {
            try Task.checkCancellation()
            input.frameLength = 0
            if file.framePosition < file.length { try file.read(into: input, frameCount: 512) }
            guard let samples = input.floatChannelData, let destination = result.floatChannelData else { break }
            var blocks = Array(repeating: [Float](repeating: 0, count: 512), count: channels)
            for channel in 0..<channels {
                var next = [Float](repeating: 0, count: 512)
                for i in 0..<Int(input.frameLength) { next[i] = samples[channel][i] }
                var spectrum = fft.forward(previous[channel] + next)
                for i in 0..<1024 {
                    let power = spectrum.real[i] * spectrum.real[i] + spectrum.imaginary[i] * spectrum.imaginary[i]
                    let reduction = max(0.1, sqrt(max(0, 1 - 1.4 * noise[i] / max(power, 0.00000001))))
                    let amount = 1 - strength + strength * reduction
                    spectrum.real[i] *= amount
                    spectrum.imaginary[i] *= amount
                }
                let cleaned = fft.inverse(spectrum)
                for i in 0..<512 {
                    blocks[channel][i] = cleaned[i] + overlap[channel][i]
                    overlap[channel][i] = cleaned[i + 512]
                }
                previous[channel] = next
            }
            if first { first = false; continue }
            let count = min(512, length - written)
            let energy = sqrt(blocks[0].prefix(count).reduce(0) { $0 + $1 * $1 } / Float(count))
            let peak = blocks.flatMap { $0.prefix(count) }.map(abs).max() ?? 0
            var target = gain
            if request.settings.normalizesSpeech && energy > max(0.003, noiseRMS * 2) {
                target = min(3, max(0.5, 0.125 / max(energy, 0.001)))
            }
            if !request.settings.normalizesSpeech { target = 1 }
            let nextGain = min(gain + (target - gain) * 0.06, 0.97 / max(peak, 0.0001))
            result.frameLength = AVAudioFrameCount(count)
            for channel in 0..<channels {
                for i in 0..<count {
                    let level = gain + (nextGain - gain) * Float(i + 1) / Float(count)
                    destination[channel][i] = min(0.98, max(-0.98, blocks[channel][i] * level))
                }
            }
            gain = nextGain
            try output.write(from: result)
            written += count
        }
        guard written == length else { throw RecorderError.mediaWriteFailed("Voice cleanup stopped before the end of the source.") }
    }
}

private final class VoiceSpectrum {
    struct Spectrum {
        var real: [Float]
        var imaginary: [Float]
    }

    private let forwardSetup: vDSP_DFT_Setup
    private let inverseSetup: vDSP_DFT_Setup
    private let window: [Float] = (0..<1024).map { sqrt(0.5 - 0.5 * cos(2 * .pi * Float($0) / 1024)) }

    init() throws {
        guard let forward = vDSP_DFT_zop_CreateSetup(nil, 1024, .FORWARD),
              let inverse = vDSP_DFT_zop_CreateSetup(nil, 1024, .INVERSE) else {
            throw RecorderError.mediaWriteFailed("Voice cleanup is unavailable on this Mac.")
        }
        forwardSetup = forward
        inverseSetup = inverse
    }

    deinit {
        vDSP_DFT_DestroySetup(forwardSetup)
        vDSP_DFT_DestroySetup(inverseSetup)
    }

    func forward(_ samples: [Float]) -> Spectrum {
        let input = zip(samples, window).map(*)
        let zeros = [Float](repeating: 0, count: 1024)
        var result = Spectrum(real: zeros, imaginary: zeros)
        vDSP_DFT_Execute(forwardSetup, input, zeros, &result.real, &result.imaginary)
        return result
    }

    func inverse(_ spectrum: Spectrum) -> [Float] {
        var real = [Float](repeating: 0, count: 1024)
        var imaginary = real
        vDSP_DFT_Execute(inverseSetup, spectrum.real, spectrum.imaginary, &real, &imaginary)
        return zip(real, window).map { $0 * $1 / 1024 }
    }
}

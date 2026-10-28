import AudioToolbox
import AVFoundation

/// Apple's voice isolation model, the one behind Voice Isolation in FaceTime and Final Cut Pro, run on a whole file
/// faster than real time. It keeps the voice nearest the microphone and removes everything else, other people talking
/// and music included: sounds a noise filter cannot tell apart from speech, because they are speech.
enum VoiceIsolation {
    private static let component = AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: kAudioUnitSubType_AUSoundIsolation,
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0,
        componentFlagsMask: 0
    )
    private static let blockFrames: AVAudioFrameCount = 4_096

    /// Whether this Mac has the model. Every Mac on macOS 15 should; the editor hides the level when it does not.
    static var isAvailable: Bool {
        var description = component
        return AudioComponentFindNext(nil, &description) != nil
    }

    struct Request {
        let source: URL
        let destination: URL
        let progress: (Double) -> Void
    }

    /// Writes the isolated voice as 32-bit float PCM with the source's rate, channels and exact length. The model
    /// hears ahead before it answers; that delay is measured from the unit and taken back out, so the voice stays on
    /// the lips.
    static func process(_ request: Request) throws {
        let file = try AVAudioFile(forReading: request.source, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        let length = file.length
        guard length > 0 else { throw RecorderError.mediaWriteFailed("The microphone source has no readable samples.") }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let effect = AVAudioUnitEffect(audioComponentDescription: component)
        engine.attach(player)
        engine.attach(effect)
        engine.connect(player, to: effect, format: format)
        engine.connect(effect, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: blockFrames)
        let quality = AudioUnitSetParameter(effect.audioUnit, AudioUnitParameterID(kAUSoundIsolationParam_SoundToIsolate),
                                            kAudioUnitScope_Global, 0,
                                            AudioUnitParameterValue(kAUSoundIsolationSoundType_HighQualityVoice), 0)
        if quality != noErr {
            NSLog("Voice isolation: high quality model unavailable (\(quality)), using the standard one")
        }
        AudioUnitSetParameter(effect.audioUnit, AudioUnitParameterID(kAUSoundIsolationParam_WetDryMixPercent),
                              kAudioUnitScope_Global, 0, 100, 0)
        try engine.start()
        defer { engine.stop() }
        player.scheduleFile(file, at: nil)
        player.play()

        let output = try AVAudioFile(forWriting: request.destination, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let rendered = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: blockFrames),
              let kept = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: blockFrames) else {
            throw RecorderError.mediaWriteFailed("Cannot allocate voice isolation buffers.")
        }
        // The unit reports its delay only once it has rendered; until then nothing is known to skip.
        var delay: AVAudioFramePosition?
        var skipped: AVAudioFramePosition = 0
        var written: AVAudioFramePosition = 0
        while written < length {
            try Task.checkCancellation()
            switch try engine.renderOffline(blockFrames, to: rendered) {
            case .success: break
            case .cannotDoInCurrentContext: continue
            case .error, .insufficientDataFromInputNode:
                throw RecorderError.mediaWriteFailed("Voice isolation stopped before the end of the microphone audio.")
            @unknown default:
                throw RecorderError.mediaWriteFailed("Voice isolation stopped before the end of the microphone audio.")
            }
            let frames = AVAudioFramePosition(rendered.frameLength)
            if delay == nil { delay = latencyFrames(effect: effect, sampleRate: format.sampleRate) }
            let skip = min(frames, max(0, (delay ?? 0) - skipped))
            skipped += skip
            let count = min(frames - skip, length - written)
            guard count > 0 else { continue }
            copy(.init(from: rendered, into: kept, start: Int(skip), count: Int(count)))
            try output.write(from: kept)
            written += count
            request.progress(Double(written) / Double(length))
        }
        // Closed here, not when the object goes away, so a reader right after this sees the whole file.
        output.close()
    }

    private static func latencyFrames(effect: AVAudioUnitEffect, sampleRate: Double) -> AVAudioFramePosition {
        var seconds = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        let status = AudioUnitGetProperty(effect.audioUnit, kAudioUnitProperty_Latency, kAudioUnitScope_Global, 0,
                                          &seconds, &size)
        guard status == noErr, seconds.isFinite, seconds > 0 else { return 0 }
        return AVAudioFramePosition((seconds * sampleRate).rounded())
    }

    private struct CopyRequest {
        let from: AVAudioPCMBuffer
        let into: AVAudioPCMBuffer
        let start: Int
        let count: Int
    }

    private static func copy(_ request: CopyRequest) {
        guard let source = request.from.floatChannelData, let destination = request.into.floatChannelData else { return }
        for channel in 0..<Int(request.into.format.channelCount) {
            (destination[channel]).update(from: source[channel] + request.start, count: request.count)
        }
        request.into.frameLength = AVAudioFrameCount(request.count)
    }
}

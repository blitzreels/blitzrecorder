import AVFoundation

extension AVAudioFile {
    /// Every frame of the file as 32-bit float, non-interleaved. One `read(into:)` can stop a few hundred frames
    /// before the end, so this reads until nothing is left.
    func readAllFrames() -> AVAudioPCMBuffer? {
        guard length > 0, length <= Int64(UInt32.max),
              let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: AVAudioFrameCount(length)),
              let chunk = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: AVAudioFrameCount(length))
        else { return nil }
        let channels = Int(processingFormat.channelCount)
        while buffer.frameLength < buffer.frameCapacity {
            chunk.frameLength = 0
            guard (try? read(into: chunk, frameCount: buffer.frameCapacity - buffer.frameLength)) != nil,
                  chunk.frameLength > 0 else { break }
            for channel in 0..<channels {
                guard let source = chunk.floatChannelData?[channel],
                      let destination = buffer.floatChannelData?[channel] else { continue }
                destination.advanced(by: Int(buffer.frameLength)).update(from: source, count: Int(chunk.frameLength))
            }
            buffer.frameLength += chunk.frameLength
        }
        return buffer.frameLength > 0 ? buffer : nil
    }
}

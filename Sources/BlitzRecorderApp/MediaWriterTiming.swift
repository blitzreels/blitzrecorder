import CoreMedia
import Foundation

struct MediaWriterPauseClock {
    private(set) var isPaused = false
    private(set) var offset = CMTime.zero
    private var startedAt: CMTime?

    mutating func pause(at hostTime: CMTime) {
        guard !isPaused else { return }
        isPaused = true
        startedAt = hostTime
    }

    mutating func resume(at hostTime: CMTime) {
        guard isPaused else { return }
        if let startedAt {
            let delta = CMTimeSubtract(hostTime, startedAt)
            if delta.isValid, delta.seconds > 0 {
                offset = CMTimeAdd(offset, delta)
            }
        }
        startedAt = nil
        isPaused = false
    }
}

extension CMSampleBuffer {
    func retimed(toPresentationTime presentationTime: CMTime) -> CMSampleBuffer? {
        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(
            self,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &count
        )
        if count <= 0 {
            count = 1
        }

        let sourceTime = CMSampleBufferGetPresentationTimeStamp(self)
        var timing = Array(
            repeating: CMSampleTimingInfo(
                duration: CMSampleBufferGetDuration(self),
                presentationTimeStamp: sourceTime,
                decodeTimeStamp: CMSampleBufferGetDecodeTimeStamp(self)
            ),
            count: count
        )

        timing.withUnsafeMutableBufferPointer { buffer in
            _ = CMSampleBufferGetSampleTimingInfoArray(
                self,
                entryCount: count,
                arrayToFill: buffer.baseAddress,
                entriesNeededOut: &count
            )
        }

        let delta = CMTimeSubtract(presentationTime, sourceTime)
        for index in timing.indices {
            if timing[index].presentationTimeStamp.isValid {
                timing[index].presentationTimeStamp = CMTimeAdd(timing[index].presentationTimeStamp, delta)
            } else {
                timing[index].presentationTimeStamp = presentationTime
            }

            if timing[index].decodeTimeStamp.isValid {
                timing[index].decodeTimeStamp = CMTimeAdd(timing[index].decodeTimeStamp, delta)
            }
        }

        var adjusted: CMSampleBuffer?
        let status = timing.withUnsafeBufferPointer { buffer in
            CMSampleBufferCreateCopyWithNewTiming(
                allocator: kCFAllocatorDefault,
                sampleBuffer: self,
                sampleTimingEntryCount: count,
                sampleTimingArray: buffer.baseAddress,
                sampleBufferOut: &adjusted
            )
        }
        guard status == noErr else { return nil }
        return adjusted
    }
}

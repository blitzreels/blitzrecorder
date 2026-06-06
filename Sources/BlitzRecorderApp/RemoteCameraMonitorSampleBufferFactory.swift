import AVFoundation
import BlitzRecorderCore
import Foundation

final class RemoteCameraMonitorSampleBufferFactory {
    private var h264FormatDescription: CMVideoFormatDescription?
    private var presentationFrameIndex: Int64 = 0
    private let previewTimescale: CMTimeScale = 600
    private let previewFrameDurationValue: CMTimeValue = 40

    func makeSampleBuffer(from frame: RemoteCameraMonitorVideoFrame) -> CMSampleBuffer? {
        guard frame.codec == .h264, frame.width > 0, frame.height > 0, !frame.data.isEmpty else {
            return nil
        }

        if let sps = frame.h264SPS, let pps = frame.h264PPS {
            h264FormatDescription = Self.makeH264FormatDescription(sps: sps, pps: pps)
        }

        guard let h264FormatDescription else {
            return nil
        }

        var blockBuffer: CMBlockBuffer?
        let createStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: frame.data.count,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: frame.data.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard createStatus == noErr, let blockBuffer else {
            return nil
        }

        let copyStatus = frame.data.withUnsafeBytes { rawBuffer in
            CMBlockBufferReplaceDataBytes(
                with: rawBuffer.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: frame.data.count
            )
        }
        guard copyStatus == noErr else {
            return nil
        }

        let presentationTime = CMTime(
            value: presentationFrameIndex * previewFrameDurationValue,
            timescale: previewTimescale
        )
        presentationFrameIndex += 1

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: previewFrameDurationValue, timescale: previewTimescale),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: CMTime.invalid
        )
        var sampleSize = frame.data.count
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: h264FormatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let sampleBuffer else {
            return nil
        }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0,
           let attachment = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary?.self) {
            CFDictionarySetValue(
                attachment,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }

        return sampleBuffer
    }

    private static func makeH264FormatDescription(sps: Data, pps: Data) -> CMVideoFormatDescription? {
        sps.withUnsafeBytes { spsRawBuffer in
            pps.withUnsafeBytes { ppsRawBuffer in
                guard let spsBaseAddress = spsRawBuffer.baseAddress,
                      let ppsBaseAddress = ppsRawBuffer.baseAddress else {
                    return nil
                }
                let parameterSetPointers = [
                    spsBaseAddress.assumingMemoryBound(to: UInt8.self),
                    ppsBaseAddress.assumingMemoryBound(to: UInt8.self)
                ]
                let parameterSetSizes = [sps.count, pps.count]
                var formatDescription: CMFormatDescription?
                let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: parameterSetPointers,
                    parameterSetSizes: parameterSetSizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &formatDescription
                )
                return status == noErr ? formatDescription : nil
            }
        }
    }
}

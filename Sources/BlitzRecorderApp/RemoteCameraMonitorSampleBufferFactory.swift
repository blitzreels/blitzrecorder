import AVFoundation
import BlitzRecorderCore
import Foundation

final class RemoteCameraMonitorSampleBufferFactory {
    private var h264FormatDescription: CMVideoFormatDescription?
    private var activeH264SPS: Data?
    private var activeH264PPS: Data?
    private var lastSequenceNumber: Int64?
    private var nextPresentationTime = CMTime.zero

    func makeSampleBuffer(from frame: RemoteCameraMonitorVideoFrame) -> CMSampleBuffer? {
        guard frame.codec == .h264, frame.width > 0, frame.height > 0, !frame.data.isEmpty else {
            return nil
        }

        if shouldResetDecoder(for: frame) {
            resetDecoderState()
        }

        if let sps = frame.h264SPS,
           let pps = frame.h264PPS,
           sps != activeH264SPS || pps != activeH264PPS {
            guard let formatDescription = Self.makeH264FormatDescription(sps: sps, pps: pps) else {
                return nil
            }
            h264FormatDescription = formatDescription
            activeH264SPS = sps
            activeH264PPS = pps
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

        let presentationTime = nextPresentationTime
        let frameDuration = Self.frameDuration(from: frame.frameDurationSeconds)
        nextPresentationTime = nextPresentationTime + frameDuration

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: frameDuration,
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

        recordAcceptedFrame(frame)
        return sampleBuffer
    }

    func shouldResetDecoder(for frame: RemoteCameraMonitorVideoFrame) -> Bool {
        if let lastSequenceNumber,
           frame.sequenceNumber <= lastSequenceNumber {
            return true
        }

        if let activeH264SPS,
           let activeH264PPS,
           let sps = frame.h264SPS,
           let pps = frame.h264PPS,
           sps != activeH264SPS || pps != activeH264PPS {
            return true
        }

        return false
    }

    func recordAcceptedFrame(_ frame: RemoteCameraMonitorVideoFrame) {
        lastSequenceNumber = frame.sequenceNumber
        if let sps = frame.h264SPS,
           let pps = frame.h264PPS {
            activeH264SPS = sps
            activeH264PPS = pps
        }
    }

    private func resetDecoderState() {
        h264FormatDescription = nil
        activeH264SPS = nil
        activeH264PPS = nil
        nextPresentationTime = .zero
    }

    private static func frameDuration(from seconds: Double?) -> CMTime {
        let fallback = 1.0 / 15.0
        let value = seconds.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? fallback
        let clamped = min(1.0 / 10.0, max(1.0 / 60.0, value))
        return CMTime(seconds: clamped, preferredTimescale: 600)
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

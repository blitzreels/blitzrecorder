import BlitzRecorderCore
@preconcurrency import AVFoundation
import CoreImage
import Foundation
import UIKit
import VideoToolbox

final class CameraMonitorPreviewDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let context = CIContext()
    private lazy var videoEncoder = CameraMonitorPreviewVideoEncoder()
    private var lastEncodedFrameDate = Date.distantPast
    private var isSuspended = false
    private var isDeliverySuspended = false
    private var loadProfile = CameraMonitorPreviewLoadProfile.normal
    var onFrame: (@Sendable (Data, Int, Int) -> Void)?
    var onVideoFrame: (@Sendable (RemoteCameraMonitorVideoFrame) -> Void)?
    var onDroppedFrame: (@Sendable () -> Void)?

    func setSuspended(_ suspended: Bool, resetEncoder: Bool) {
        isSuspended = suspended
        lastEncodedFrameDate = .distantPast
        if resetEncoder {
            videoEncoder.reset()
        }
    }

    func setDeliverySuspended(_ suspended: Bool) {
        isDeliverySuspended = suspended
        if suspended {
            lastEncodedFrameDate = .distantPast
        }
    }

    func setLoadProfile(_ profile: CameraMonitorPreviewLoadProfile) {
        guard loadProfile != profile else { return }
        loadProfile = profile
        lastEncodedFrameDate = .distantPast
        videoEncoder.reset()
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !isSuspended else {
            return
        }
        guard !isDeliverySuspended else {
            return
        }

        let now = Date()
        let profile = loadProfile
        guard now.timeIntervalSince(lastEncodedFrameDate) >= profile.frameDurationSeconds else {
            return
        }
        lastEncodedFrameDate = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        videoEncoder.onFrame = onVideoFrame
        if videoEncoder.encode(sampleBuffer: sampleBuffer, pixelBuffer: pixelBuffer, profile: profile) {
            return
        }

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let targetWidth = profile.targetWidth
        let scale = CGFloat(targetWidth) / max(image.extent.width, 1)
        let targetHeight = max(1, Int(image.extent.height * scale))
        let scaledImage = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let outputRect = CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
        guard let cgImage = context.createCGImage(scaledImage, from: outputRect),
              let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: profile.jpegCompressionQuality) else {
            return
        }

        onFrame?(data, targetWidth, targetHeight)
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        onDroppedFrame?()
    }
}

enum CameraMonitorPreviewLoadProfile: Int, Comparable {
    case normal
    case reduced
    case minimal

    static func < (
        lhs: CameraMonitorPreviewLoadProfile,
        rhs: CameraMonitorPreviewLoadProfile
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var targetWidth: Int {
        switch self {
        case .normal: return 720
        case .reduced: return 540
        case .minimal: return 420
        }
    }

    var frameRate: Int {
        switch self {
        case .normal: return 24
        case .reduced: return 18
        case .minimal: return 12
        }
    }

    var frameDurationSeconds: TimeInterval {
        1.0 / Double(frameRate)
    }

    var averageBitRate: Int {
        switch self {
        case .normal: return 1_200_000
        case .reduced: return 650_000
        case .minimal: return 360_000
        }
    }

    var keyFrameInterval: Int {
        frameRate * 2
    }

    var jpegCompressionQuality: CGFloat {
        switch self {
        case .normal: return 0.62
        case .reduced: return 0.55
        case .minimal: return 0.48
        }
    }
}

private final class CameraMonitorPreviewVideoEncoder: @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private var compressionSession: VTCompressionSession?
    private var pixelBufferPool: CVPixelBufferPool?
    private var encodedWidth = 0
    private var encodedHeight = 0
    private var encodedFrameDurationSeconds = CameraMonitorPreviewLoadProfile.normal.frameDurationSeconds
    private var sequenceNumber: Int64 = 0
    private var didFail = false

    var onFrame: (@Sendable (RemoteCameraMonitorVideoFrame) -> Void)?

    func reset() {
        compressionSession.map { VTCompressionSessionInvalidate($0) }
        compressionSession = nil
        pixelBufferPool = nil
        encodedWidth = 0
        encodedHeight = 0
        encodedFrameDurationSeconds = CameraMonitorPreviewLoadProfile.normal.frameDurationSeconds
        didFail = false
    }

    func encode(
        sampleBuffer: CMSampleBuffer,
        pixelBuffer sourcePixelBuffer: CVPixelBuffer,
        profile: CameraMonitorPreviewLoadProfile
    ) -> Bool {
        guard !didFail else { return false }

        let sourceWidth = CVPixelBufferGetWidth(sourcePixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(sourcePixelBuffer)
        guard sourceWidth > 0, sourceHeight > 0 else { return false }

        let targetWidth = profile.targetWidth
        let scaledHeight = Int((Double(sourceHeight) * Double(targetWidth) / Double(sourceWidth)).rounded())
        let targetHeight = max(2, scaledHeight + (scaledHeight % 2))

        guard configureIfNeeded(width: targetWidth, height: targetHeight, profile: profile),
              let outputPixelBuffer = makeOutputPixelBuffer(width: targetWidth, height: targetHeight) else {
            didFail = true
            return false
        }

        let image = CIImage(cvPixelBuffer: sourcePixelBuffer)
        let scale = CGFloat(targetWidth) / max(image.extent.width, 1)
        let scaledImage = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        context.render(
            scaledImage,
            to: outputPixelBuffer,
            bounds: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight),
            colorSpace: colorSpace
        )

        let sourcePTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let pts = sourcePTS.isValid ? sourcePTS : CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 1_000_000)
        var flags: VTEncodeInfoFlags = []
        let status = VTCompressionSessionEncodeFrame(
            compressionSession!,
            imageBuffer: outputPixelBuffer,
            presentationTimeStamp: pts,
            duration: CMTime(value: 1, timescale: CMTimeScale(profile.frameRate)),
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: &flags
        )
        if status != noErr {
            didFail = true
            return false
        }
        return true
    }

    private func configureIfNeeded(
        width: Int,
        height: Int,
        profile: CameraMonitorPreviewLoadProfile
    ) -> Bool {
        guard compressionSession == nil || width != encodedWidth || height != encodedHeight else {
            return true
        }

        compressionSession.map { VTCompressionSessionInvalidate($0) }
        compressionSession = nil
        pixelBufferPool = nil
        encodedWidth = width
        encodedHeight = height
        encodedFrameDurationSeconds = profile.frameDurationSeconds

        let encoderSpec = [
            kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true,
            kVTVideoEncoderSpecification_EnableLowLatencyRateControl as String: true
        ] as CFDictionary
        let sourceAttributes = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ] as CFDictionary

        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: encoderSpec,
            imageBufferAttributes: sourceAttributes,
            compressedDataAllocator: nil,
            outputCallback: Self.compressionOutputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &session
        )
        guard status == noErr, let session else {
            return false
        }

        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxFrameDelayCount, value: 1 as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: profile.frameRate as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: profile.averageBitRate as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: profile.keyFrameInterval as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Baseline_AutoLevel)
        VTCompressionSessionPrepareToEncodeFrames(session)
        compressionSession = session

        let poolAttributes = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 3
        ] as CFDictionary
        CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttributes, sourceAttributes, &pixelBufferPool)
        return pixelBufferPool != nil
    }

    private func makeOutputPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        if let pixelBufferPool {
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &pixelBuffer)
            if pixelBuffer != nil {
                return pixelBuffer
            }
        }
        let attributes = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes, &pixelBuffer)
        return pixelBuffer
    }

    private static let compressionOutputCallback: VTCompressionOutputCallback = { refcon, _, status, _, sampleBuffer in
        guard status == noErr,
              let refcon,
              let sampleBuffer else {
            return
        }
        let encoder = Unmanaged<CameraMonitorPreviewVideoEncoder>.fromOpaque(refcon).takeUnretainedValue()
        encoder.handleEncodedSampleBuffer(sampleBuffer)
    }

    private func handleEncodedSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer),
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return
        }

        let byteCount = CMBlockBufferGetDataLength(dataBuffer)
        guard byteCount > 0 else { return }

        var data = Data(count: byteCount)
        let copyStatus = data.withUnsafeMutableBytes { rawBuffer in
            CMBlockBufferCopyDataBytes(
                dataBuffer,
                atOffset: 0,
                dataLength: byteCount,
                destination: rawBuffer.baseAddress!
            )
        }
        guard copyStatus == noErr else { return }

        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
        let isKeyFrame: Bool
        if let attachments,
           CFArrayGetCount(attachments) > 0,
           let attachment = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFDictionary?.self) {
            isKeyFrame = !CFDictionaryContainsKey(
                attachment,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque()
            )
        } else {
            isKeyFrame = true
        }

        var sps: Data?
        var pps: Data?
        if isKeyFrame {
            sps = h264ParameterSetData(from: formatDescription, index: 0)
            pps = h264ParameterSetData(from: formatDescription, index: 1)
        }

        sequenceNumber += 1
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let frame = RemoteCameraMonitorVideoFrame(
            codec: .h264,
            data: data,
            width: encodedWidth,
            height: encodedHeight,
            presentationTimeSeconds: pts.isValid ? CMTimeGetSeconds(pts) : CACurrentMediaTime(),
            frameDurationSeconds: encodedFrameDurationSeconds,
            isKeyFrame: isKeyFrame,
            sequenceNumber: sequenceNumber,
            h264SPS: sps,
            h264PPS: pps
        )
        onFrame?(frame)
    }

    private func h264ParameterSetData(from formatDescription: CMFormatDescription, index: Int) -> Data? {
        var parameterSetPointer: UnsafePointer<UInt8>?
        var parameterSetSize = 0
        var parameterSetCount = 0
        var nalUnitHeaderLength: Int32 = 0
        let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            formatDescription,
            parameterSetIndex: index,
            parameterSetPointerOut: &parameterSetPointer,
            parameterSetSizeOut: &parameterSetSize,
            parameterSetCountOut: &parameterSetCount,
            nalUnitHeaderLengthOut: &nalUnitHeaderLength
        )
        guard status == noErr, let parameterSetPointer, parameterSetSize > 0 else {
            return nil
        }
        return Data(bytes: parameterSetPointer, count: parameterSetSize)
    }
}

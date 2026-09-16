import AVFoundation
import CoreVideo
import Darwin

enum CaptureFailureRecoveryDecision: Equatable {
    case continueWithBlackCamera
    case stopTake
}

struct CaptureFailureRecovery {
    struct Request {
        let source: CaptureSource
        let enabledSources: Set<CaptureSource>
        var usesLiveCompositor: Bool = false
        var usesRemoteCamera: Bool = false
    }

    static let blackCameraWarning = "Camera unavailable. Recording continues with a black Camera source."

    static func decision(_ request: Request) -> CaptureFailureRecoveryDecision {
        if request.source == .camera,
            request.enabledSources.contains(.screen),
            !request.usesLiveCompositor,
            !request.usesRemoteCamera
        {
            return .continueWithBlackCamera
        }
        return .stopTake
    }
}

final class CameraBlackFrameGenerator: @unchecked Sendable {
    struct Request {
        let width: Int
        let height: Int
        let pixelFormat: OSType
        let framesPerSecond: Int
    }

    let frameDuration: CMTime

    private let pixelBuffer: CVPixelBuffer
    private let formatDescription: CMVideoFormatDescription

    init(_ request: Request) throws {
        var pixelBuffer: CVPixelBuffer?
        let pixelBufferStatus = CVPixelBufferCreate(
            kCFAllocatorDefault,
            request.width,
            request.height,
            request.pixelFormat,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
            &pixelBuffer
        )
        guard pixelBufferStatus == kCVReturnSuccess, let pixelBuffer else {
            throw RecorderError.writerNotReady
        }
        Self.fillBlack(pixelBuffer)

        var formatDescription: CMVideoFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let formatDescription else {
            throw RecorderError.writerNotReady
        }

        self.pixelBuffer = pixelBuffer
        self.formatDescription = formatDescription
        frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, request.framesPerSecond)))
    }

    func sampleBuffer(at presentationTime: CMTime) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(
            duration: frameDuration,
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr else { return nil }
        return sampleBuffer
    }

    private static func fillBlack(_ pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        if CVPixelBufferGetPlaneCount(pixelBuffer) == 2 {
            if let luma = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) {
                memset(
                    luma,
                    0,
                    CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
                        * CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
                )
            }
            if let chroma = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) {
                memset(
                    chroma,
                    128,
                    CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
                        * CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
                )
            }
            return
        }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        memset(baseAddress, 0, bytesPerRow * height)
        if CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA {
            let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
            let width = CVPixelBufferGetWidth(pixelBuffer)
            for y in 0..<height {
                for x in 0..<width {
                    bytes[y * bytesPerRow + x * 4 + 3] = 255
                }
            }
        }
    }
}

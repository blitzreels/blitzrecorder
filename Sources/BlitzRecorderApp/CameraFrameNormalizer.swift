import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation

struct CameraFrameNormalizationPlan: Equatable {
    let cropRect: CGRect

    var outputSize: CGSize {
        cropRect.size
    }
}

struct CameraFrameLetterboxDetectionRequest {
    let pixelBuffer: CVPixelBuffer
}

struct CameraFrameNormalizationStartupRequest {
    let sourceSize: CGSize
    let bufferedSampleCount: Int
    let normalizationPlan: CameraFrameNormalizationPlan?
}

enum CameraFrameNormalizationStartupDecision: Equatable {
    case waitForMoreSamples
    case start(CameraFrameNormalizationPlan?)
}

enum CameraFrameNormalizationStartupPolicy {
    static let portraitSampleLimit = 8

    static func decision(
        _ request: CameraFrameNormalizationStartupRequest
    ) -> CameraFrameNormalizationStartupDecision {
        if let normalizationPlan = request.normalizationPlan {
            return .start(normalizationPlan)
        }
        if request.sourceSize.width >= request.sourceSize.height * 0.9 {
            return .start(nil)
        }
        if request.bufferedSampleCount < portraitSampleLimit {
            return .waitForMoreSamples
        }
        return .start(nil)
    }
}

enum CameraFrameLetterboxDetector {
    private static let landscapeAspectRatio = 16.0 / 9.0

    static func normalizationPlan(
        _ request: CameraFrameLetterboxDetectionRequest
    ) -> CameraFrameNormalizationPlan? {
        let pixelBuffer = request.pixelBuffer
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard height > Int(Double(width) * 1.1),
              let layout = CameraFramePixelLayout(pixelFormat: CVPixelBufferGetPixelFormatType(pixelBuffer)) else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let baseAddress = layout.isPacked
            ? CVPixelBufferGetBaseAddress(pixelBuffer)
            : CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)
        guard let baseAddress else { return nil }

        let bytesPerRow = layout.isPacked
            ? CVPixelBufferGetBytesPerRow(pixelBuffer)
            : CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        let sampleStep = max(1, width / 128)
        let blackThreshold = layout.blackThreshold

        func samples(_ row: Int) -> [UInt8] {
            let rowAddress = bytes.advanced(by: row * bytesPerRow)
            return stride(from: 0, to: width, by: sampleStep).map {
                rowAddress[$0 * layout.bytesPerSample + layout.brightnessOffset]
            }
        }

        func nonDarkFraction(_ row: Int) -> Double {
            let values = samples(row)
            guard !values.isEmpty else { return 0 }
            return Double(values.filter { $0 > blackThreshold }.count) / Double(values.count)
        }

        func beginsActiveImage(_ row: Int) -> Bool {
            let probes = [row, row + 2, row + 4].filter { $0 < height }
            return probes.count == 3 && probes.allSatisfy { nonDarkFraction($0) >= 0.15 }
        }

        func endsActiveImage(_ row: Int) -> Bool {
            let probes = [row, row - 2, row - 4].filter { $0 >= 0 }
            return probes.count == 3 && probes.allSatisfy { nonDarkFraction($0) >= 0.15 }
        }

        func isBlackBar(_ row: Int) -> Bool {
            let values = samples(row)
            guard let low = values.min(), let high = values.max() else { return false }
            return high <= blackThreshold && high - low <= 6
        }

        func centeredLandscapeBand() -> Range<Int>? {
            let bandHeight = evenRounded(Double(width) / landscapeAspectRatio)
            let top = evenRounded(Double(height - bandHeight) / 2)
            guard bandHeight > 0, top > 0, top + bandHeight < height else { return nil }
            let step = max(1, height / 96)
            let outside = Array(stride(from: 0, to: top - 2, by: step))
                + Array(stride(from: top + bandHeight + 2, to: height, by: step))
            let inside = stride(from: top, to: top + bandHeight, by: step)
            guard outside.allSatisfy(isBlackBar), inside.contains(where: { !isBlackBar($0) }) else { return nil }
            return top..<(top + bandHeight)
        }

        func plan(_ band: Range<Int>) -> CameraFrameNormalizationPlan {
            CameraFrameNormalizationPlan(cropRect: CGRect(x: 0, y: band.lowerBound, width: width, height: band.count))
        }

        guard let rawTop = (0..<height).first(where: beginsActiveImage),
              let rawBottom = (0..<height).reversed().first(where: endsActiveImage) else {
            return centeredLandscapeBand().map(plan)
        }

        let top = rawTop + rawTop % 2
        let bottomExclusive = (rawBottom + 1) - (rawBottom + 1) % 2
        let cropHeight = bottomExclusive - top
        let bottomPadding = height - bottomExclusive
        let minimumPadding = Int(Double(height) * 0.12)
        let symmetryTolerance = max(8, Int(Double(height) * 0.04))
        guard cropHeight > 0,
              top >= minimumPadding,
              bottomPadding >= minimumPadding,
              abs(top - bottomPadding) <= symmetryTolerance else {
            return centeredLandscapeBand().map(plan)
        }

        let contentAspectRatio = Double(width) / Double(cropHeight)
        guard (1.25...2.4).contains(contentAspectRatio) else {
            return centeredLandscapeBand().map(plan)
        }

        return plan(top..<bottomExclusive)
    }

    private static func evenRounded(_ value: Double) -> Int {
        Int((value / 2).rounded()) * 2
    }
}

struct CameraFramePixelLayout {
    let isPacked: Bool
    let bytesPerSample: Int
    let brightnessOffset: Int
    let blackThreshold: UInt8

    init?(pixelFormat: OSType) {
        switch pixelFormat {
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            self.init(isPacked: false, bytesPerSample: 1, brightnessOffset: 0, blackThreshold: 24)
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            self.init(isPacked: false, bytesPerSample: 1, brightnessOffset: 0, blackThreshold: 36)
        case kCVPixelFormatType_32BGRA:
            self.init(isPacked: true, bytesPerSample: 4, brightnessOffset: 1, blackThreshold: 24)
        default:
            return nil
        }
    }

    private init(isPacked: Bool, bytesPerSample: Int, brightnessOffset: Int, blackThreshold: UInt8) {
        self.isPacked = isPacked
        self.bytesPerSample = bytesPerSample
        self.brightnessOffset = brightnessOffset
        self.blackThreshold = blackThreshold
    }
}

final class CameraFrameNormalizer {
    private let plan: CameraFrameNormalizationPlan
    private var pixelBufferPool: CVPixelBufferPool?
    private var poolPixelFormat: OSType?

    init(plan: CameraFrameNormalizationPlan) {
        self.plan = plan
    }

    func normalize(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard let sourcePixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let destinationPixelBuffer = croppedPixelBuffer(sourcePixelBuffer) else {
            return nil
        }

        var formatDescription: CMVideoFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: destinationPixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let formatDescription else {
            return nil
        }

        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sampleBuffer),
            presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
            decodeTimeStamp: CMSampleBufferGetDecodeTimeStamp(sampleBuffer)
        )
        var normalizedSampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: destinationPixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &normalizedSampleBuffer
        )
        guard sampleStatus == noErr else { return nil }
        return normalizedSampleBuffer
    }

    private func croppedPixelBuffer(
        _ sourcePixelBuffer: CVPixelBuffer
    ) -> CVPixelBuffer? {
        let pixelFormat = CVPixelBufferGetPixelFormatType(sourcePixelBuffer)
        guard let layout = CameraFramePixelLayout(pixelFormat: pixelFormat) else { return nil }

        let cropX = Int(plan.cropRect.minX)
        let cropY = Int(plan.cropRect.minY)
        let outputWidth = Int(plan.cropRect.width)
        let outputHeight = Int(plan.cropRect.height)
        guard cropX >= 0,
              cropY >= 0,
              cropX % 2 == 0,
              cropY % 2 == 0,
              outputWidth > 0,
              outputHeight > 0,
              outputWidth % 2 == 0,
              outputHeight % 2 == 0,
              cropX + outputWidth <= CVPixelBufferGetWidth(sourcePixelBuffer),
              cropY + outputHeight <= CVPixelBufferGetHeight(sourcePixelBuffer) else {
            return nil
        }

        let pool = pixelBufferPool(for: pixelFormat)
        var destinationPixelBuffer: CVPixelBuffer?
        let createStatus = pool.map {
            CVPixelBufferPoolCreatePixelBuffer(
                kCFAllocatorDefault,
                $0,
                &destinationPixelBuffer
            )
        } ?? kCVReturnInvalidArgument
        guard createStatus == kCVReturnSuccess, let destinationPixelBuffer else {
            return nil
        }

        CVBufferPropagateAttachments(sourcePixelBuffer, destinationPixelBuffer)
        CVPixelBufferLockBaseAddress(sourcePixelBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(destinationPixelBuffer, [])
        defer {
            CVPixelBufferUnlockBaseAddress(destinationPixelBuffer, [])
            CVPixelBufferUnlockBaseAddress(sourcePixelBuffer, .readOnly)
        }

        if layout.isPacked {
            guard let sourceBaseAddress = CVPixelBufferGetBaseAddress(sourcePixelBuffer),
                  let destinationBaseAddress = CVPixelBufferGetBaseAddress(destinationPixelBuffer) else {
                return nil
            }
            let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(sourcePixelBuffer)
            let destinationBytesPerRow = CVPixelBufferGetBytesPerRow(destinationPixelBuffer)
            for row in 0..<outputHeight {
                memcpy(
                    destinationBaseAddress.advanced(by: row * destinationBytesPerRow),
                    sourceBaseAddress.advanced(
                        by: (cropY + row) * sourceBytesPerRow + cropX * layout.bytesPerSample
                    ),
                    outputWidth * layout.bytesPerSample
                )
            }
            return destinationPixelBuffer
        }

        for plane in 0..<2 {
            guard let sourceBaseAddress = CVPixelBufferGetBaseAddressOfPlane(sourcePixelBuffer, plane),
                  let destinationBaseAddress = CVPixelBufferGetBaseAddressOfPlane(destinationPixelBuffer, plane) else {
                return nil
            }
            let verticalScale = plane == 0 ? 1 : 2
            let sourceBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(sourcePixelBuffer, plane)
            let destinationBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(destinationPixelBuffer, plane)
            let sourceStartRow = cropY / verticalScale
            let rowCount = outputHeight / verticalScale
            for row in 0..<rowCount {
                memcpy(
                    destinationBaseAddress.advanced(by: row * destinationBytesPerRow),
                    sourceBaseAddress.advanced(
                        by: (sourceStartRow + row) * sourceBytesPerRow + cropX
                    ),
                    outputWidth
                )
            }
        }
        return destinationPixelBuffer
    }

    private func pixelBufferPool(
        for pixelFormat: OSType
    ) -> CVPixelBufferPool? {
        if poolPixelFormat == pixelFormat, let pixelBufferPool {
            return pixelBufferPool
        }

        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            [kCVPixelBufferPoolMinimumBufferCountKey: 4] as CFDictionary,
            [
                kCVPixelBufferPixelFormatTypeKey: pixelFormat,
                kCVPixelBufferWidthKey: Int(plan.outputSize.width),
                kCVPixelBufferHeightKey: Int(plan.outputSize.height),
                kCVPixelBufferIOSurfacePropertiesKey: [:],
                kCVPixelBufferMetalCompatibilityKey: true
            ] as CFDictionary,
            &pool
        )
        guard status == kCVReturnSuccess, let pool else { return nil }
        pixelBufferPool = pool
        poolPixelFormat = pixelFormat
        return pool
    }
}

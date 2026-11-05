import CoreImage
import CoreVideo
import Foundation
import IOSurface

final class CameraPopoutPreview: @unchecked Sendable {
    struct Request: @unchecked Sendable {
        let image: CIImage
        let grade: CameraColorGrade
        let style: CameraPopoutStyle?
        let maxDimension: CGFloat
        let completion: @MainActor (CVPixelBuffer?) -> Void
    }

    private let queue = DispatchQueue(label: "blitzrecorder.camera-popout", qos: .userInitiated)
    private let renderer = CameraPopoutRenderer()
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    private var pool: CVPixelBufferPool?
    private var poolSize = CGSize.zero

    func render(_ request: Request) {
        queue.async { [self] in
            let graded = request.grade.applied(to: request.grade.cameraInput(from: request.image))
            let scale = min(1, request.maxDimension / max(graded.extent.width, graded.extent.height))
            let input = graded.transformed(by: .init(scaleX: scale, y: scale))
            let result = request.style.map { renderer.image(.init(image: input, style: $0)) } ?? input
            let picture = renderedPicture(result)
            Task { @MainActor in request.completion(picture) }
        }
    }

    struct StillRequest: @unchecked Sendable {
        let image: CIImage
        let maxDimension: CGFloat
        let completion: @MainActor (CGImage?) -> Void
    }

    func still(_ request: StillRequest) {
        queue.async { [self] in
            let scale = min(1, request.maxDimension / max(request.image.extent.width, request.image.extent.height))
            let input = request.image.transformed(by: .init(scaleX: scale, y: scale))
            let image = context.createCGImage(input, from: input.extent)
            Task { @MainActor in request.completion(image) }
        }
    }

    private func renderedPicture(_ image: CIImage) -> CVPixelBuffer? {
        let extent = image.extent.integral
        guard let buffer = pixelBuffer(size: extent.size) else { return nil }
        let destination = CIRenderDestination(pixelBuffer: buffer)
        destination.colorSpace = colorSpace
        destination.alphaMode = .premultiplied
        let placed = image.transformed(by: .init(translationX: -extent.minX, y: -extent.minY))
        do {
            try context.startTask(toClear: destination).waitUntilCompleted()
            try context.startTask(toRender: placed, to: destination).waitUntilCompleted()
            return buffer
        } catch {
            return nil
        }
    }

    private func pixelBuffer(size: CGSize) -> CVPixelBuffer? {
        if poolSize != size {
            poolSize = size
            pool = nil
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        }
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        if let buffer, let surface = CVPixelBufferGetIOSurface(buffer)?.takeUnretainedValue(),
           let name = colorSpace?.copyPropertyList() {
            IOSurfaceSetValue(surface, kIOSurfaceColorSpace, name)
        }
        return buffer
    }
}

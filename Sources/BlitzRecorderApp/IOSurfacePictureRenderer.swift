import CoreImage
import CoreVideo
import Foundation
import IOSurface

/// Renders Core Image pictures into reused IOSurface-backed buffers. A layer shows such a buffer, and Core Image
/// reads it, without copying the pixels through the CPU. Use it from one queue.
final class IOSurfacePictureRenderer: @unchecked Sendable {
    struct Request {
        let image: CIImage
        let context: CIContext
    }

    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    private var pool: CVPixelBufferPool?
    private var poolSize = CGSize.zero

    /// The picture's integral extent, drawn from the buffer's origin.
    func render(_ request: Request) -> CVPixelBuffer? {
        let extent = request.image.extent.integral
        guard !extent.isInfinite, extent.width > 0, extent.height > 0,
              let buffer = pixelBuffer(size: extent.size) else { return nil }
        let destination = CIRenderDestination(pixelBuffer: buffer)
        destination.colorSpace = colorSpace
        destination.alphaMode = .premultiplied
        let placed = request.image.transformed(by: .init(translationX: -extent.minX, y: -extent.minY))
        do {
            try request.context.startTask(toClear: destination).waitUntilCompleted()
            try request.context.startTask(toRender: placed, to: destination).waitUntilCompleted()
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

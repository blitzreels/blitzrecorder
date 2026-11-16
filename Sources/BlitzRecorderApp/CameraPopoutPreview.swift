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
    private let renderer = CameraPopoutRenderer(quality: .playback)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let pictures = IOSurfacePictureRenderer()

    func render(_ request: Request) {
        queue.async { [self] in
            let graded = request.grade.applied(to: request.grade.cameraInput(from: request.image))
            let scale = min(1, request.maxDimension / max(graded.extent.width, graded.extent.height))
            let input = graded.transformed(by: .init(scaleX: scale, y: scale))
            let result = request.style.map { renderer.image(.init(image: input, style: $0)) } ?? input
            let picture = pictures.render(.init(image: result, context: context))
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

}

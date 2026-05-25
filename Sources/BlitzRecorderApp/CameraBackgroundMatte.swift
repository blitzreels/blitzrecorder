import AVFoundation
import CoreImage
import Foundation
import Vision

enum CameraBackgroundMatte {
    static func mattedImage(
        for pixelBuffer: CVPixelBuffer,
        request: VNGeneratePersonSegmentationRequest,
        sequenceHandler: VNSequenceRequestHandler
    ) -> CIImage {
        let originalImage = CIImage(cvPixelBuffer: pixelBuffer)
        do {
            try sequenceHandler.perform([request], on: pixelBuffer, orientation: .up)
            guard let maskPixelBuffer = request.results?.first?.pixelBuffer else {
                return transparentImage(matching: originalImage)
            }

            var maskImage = CIImage(cvPixelBuffer: maskPixelBuffer)
            let scaleX = originalImage.extent.width / max(1, maskImage.extent.width)
            let scaleY = originalImage.extent.height / max(1, maskImage.extent.height)
            maskImage = maskImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

            let transparentBackground = transparentImage(matching: originalImage)
            guard let blend = CIFilter(name: "CIBlendWithMask") else {
                return transparentBackground
            }
            blend.setValue(originalImage, forKey: kCIInputImageKey)
            blend.setValue(transparentBackground, forKey: kCIInputBackgroundImageKey)
            blend.setValue(maskImage, forKey: kCIInputMaskImageKey)
            return blend.outputImage?.cropped(to: originalImage.extent) ?? transparentBackground
        } catch {
            return transparentImage(matching: originalImage)
        }
    }

    private static func transparentImage(matching image: CIImage) -> CIImage {
        CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
            .cropped(to: image.extent)
    }
}

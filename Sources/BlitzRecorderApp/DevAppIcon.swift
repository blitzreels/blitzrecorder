import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

enum DevAppIcon {
    /// Mint ≈ 158° → amber ≈ 35°, same shift as `Scripts/make-icon.swift --dev`.
    static let hueRadians = -123 * CGFloat.pi / 180

    static func tinted(_ image: NSImage) -> NSImage {
        guard let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let input = CIImage(bitmapImageRep: bitmap)
        else { return image }
        let filter = CIFilter.hueAdjust()
        filter.inputImage = input
        filter.angle = Float(hueRadians)
        guard let output = filter.outputImage else { return image }
        let representation = NSCIImageRep(ciImage: output)
        let tinted = NSImage(size: representation.size)
        tinted.addRepresentation(representation)
        return tinted
    }
}

import CoreGraphics
import Foundation

enum ProjectThumbnailSampling {
    static func times(duration: Double) -> [Double] {
        guard duration.isFinite, duration > 0 else { return [0] }
        let last = max(0, duration - 0.1)
        return Array(Set([min(2, duration * 0.1), duration * 0.25, duration * 0.6].map { min(last, $0) })).sorted()
    }

    static func detailScore(_ image: CGImage) -> Double {
        let width = 64
        let height = 36
        var pixels = [UInt8](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let mean = pixels.reduce(0.0) { $0 + Double($1) } / Double(pixels.count)
        let variance = pixels.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(pixels.count)
        var edges = 0.0
        for row in 0..<height {
            for column in 1..<width {
                let index = row * width + column
                edges += abs(Double(pixels[index]) - Double(pixels[index - 1]))
            }
        }
        return variance + edges / Double(pixels.count) * 8
    }
}

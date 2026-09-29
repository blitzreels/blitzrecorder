import AppKit
import ImageIO

enum SystemWallpaperImageCache {
    private static let lock = NSLock()
    private static var sourceCache: [String: CGImage] = [:]
    private static var renderCache: [RenderKey: CGImage] = [:]

    static func sourceImage(for candidates: [String], minimumLongEdge: Int) -> CGImage? {
        for path in candidates {
            if let cached = cachedSource(for: path),
               max(cached.width, cached.height) >= minimumLongEdge {
                return cached
            }
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let url = URL(fileURLWithPath: path)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                continue
            }
            guard max(image.width, image.height) >= minimumLongEdge else {
                continue
            }
            lock.lock()
            sourceCache[path] = image
            lock.unlock()
            return image
        }
        return nil
    }

    static func aspectFill(
        _ image: CGImage,
        pixelWidth: Int,
        pixelHeight: Int,
        representative: CGColor
    ) -> CGImage? {
        let width = max(1, pixelWidth)
        let height = max(1, pixelHeight)
        let key = RenderKey(sourceID: ObjectIdentifier(image), width: width, height: height)
        lock.lock()
        if let cached = renderCache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let target = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.setFillColor(representative)
        ctx.fill(target)

        let sourceSize = CGSize(width: image.width, height: image.height)
        let scale = max(target.width / sourceSize.width, target.height / sourceSize.height)
        let drawSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let drawRect = CGRect(
            x: (target.width - drawSize.width) / 2,
            y: (target.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        ctx.interpolationQuality = .high
        ctx.draw(image, in: drawRect)

        guard let rendered = ctx.makeImage() else { return nil }
        lock.lock()
        renderCache[key] = rendered
        if renderCache.count > 80 {
            renderCache.removeAll(keepingCapacity: true)
            renderCache[key] = rendered
        }
        lock.unlock()
        return rendered
    }

    private static func cachedSource(for path: String) -> CGImage? {
        lock.lock()
        let image = sourceCache[path]
        lock.unlock()
        return image
    }

    private struct RenderKey: Hashable {
        var sourceID: ObjectIdentifier
        var width: Int
        var height: Int
    }
}

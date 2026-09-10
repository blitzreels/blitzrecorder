import AppKit
import CoreImage

struct CursorPresentationStyle: Codable, Equatable, Sendable {
    var smoothed = true
    var scale = 1.5
    var emphasizesClicks = true

    static let standard = CursorPresentationStyle()
}

struct CursorPresentationSample: Equatable, Sendable {
    let position: CGPoint
    let clickAge: Double
    let rotation: Double
}

struct CursorPresentationTrack: Sendable {
    private let samples: [RecordingCursorSample]
    private let positions: [CGPoint]
    private let latestClicks: [Double]
    private let trimOffset: Double
    let isEmpty: Bool

    struct Request {
        let track: RecordingCursorTrack
        let trimOffset: Double
    }

    static let empty = CursorPresentationTrack(.init(track: .init(version: 2, samples: []), trimOffset: 0))

    init(_ request: Request) {
        trimOffset = request.trimOffset
        let samples = request.track.version == 2 ? request.track.samples.filter {
            $0.time.isFinite && $0.x.isFinite && $0.y.isFinite
        }.sorted { $0.time < $1.time } : []
        var smoothed: [CGPoint] = []
        var clicks: [Double] = []
        var lastClick = -Double.infinity
        smoothed.reserveCapacity(samples.count)
        clicks.reserveCapacity(samples.count)
        for index in samples.indices {
            if index.isMultiple(of: 1_024), Task.isCancelled {
                self.samples = []
                positions = []
                latestClicks = []
                isEmpty = true
                return
            }
            let sample = samples[index]
            if index > 0, samples[index - 1].segment != sample.segment { lastClick = -.infinity }
            if sample.clicked { lastClick = sample.time }
            clicks.append(lastClick)
            var weighted = CGPoint.zero
            var total = 0.0
            let lower = max(0, index - 6)
            let upper = min(samples.count - 1, index + 6)
            for neighbor in samples[lower...upper] where neighbor.visible == sample.visible
                && neighbor.rendered == sample.rendered && neighbor.segment == sample.segment {
                let delta = abs(neighbor.time - sample.time)
                guard delta < 0.1 else { continue }
                let weight = exp(-pow(delta / 0.035, 2) / 2)
                weighted.x += neighbor.x * weight
                weighted.y += neighbor.y * weight
                total += weight
            }
            let position = CGPoint(x: sample.x, y: sample.y)
            smoothed.append(sample.clicked || total == 0 ? position
                : CGPoint(x: weighted.x / total, y: weighted.y / total))
        }
        self.samples = samples
        isEmpty = !samples.contains(where: \.rendered)
        positions = smoothed
        latestClicks = clicks
    }

    struct LoadRequest: Sendable {
        let directory: URL
        let trimOffset: Double
    }

    static func load(_ request: LoadRequest) -> Self {
        let url = request.directory.appendingPathComponent("cursor-track.json")
        guard !Task.isCancelled, let data = try? Data(contentsOf: url),
              let track = try? JSONDecoder().decode(RecordingCursorTrack.self, from: data),
              !Task.isCancelled else { return .empty }
        return Self(.init(track: track, trimOffset: request.trimOffset))
    }

    struct SampleRequest {
        let time: Double
        let style: CursorPresentationStyle
    }

    func sample(_ request: SampleRequest) -> CursorPresentationSample? {
        let time = request.time + trimOffset
        guard time.isFinite, let first = samples.first, let last = samples.last,
              time >= first.time, time <= last.time + 0.15 else { return nil }
        var lower = 0
        var upper = samples.count
        while lower + 1 < upper {
            let middle = (lower + upper) / 2
            if samples[middle].time <= time { lower = middle } else { upper = middle }
        }
        let from = samples[lower]
        guard from.visible, from.rendered, time - from.time < 0.15 else { return nil }
        let next = min(lower + 1, samples.count - 1)
        let to = samples[next]
        let span = to.time - from.time
        let continuous = to.visible && to.rendered && to.segment == from.segment && span > 0 && span < 0.15
        let progress = continuous ? min(1, max(0, (time - from.time) / span)) : 0
        let start = request.style.smoothed ? positions[lower] : CGPoint(x: from.x, y: from.y)
        let end = request.style.smoothed ? positions[next] : CGPoint(x: to.x, y: to.y)
        let position = CGPoint(x: start.x + (end.x - start.x) * progress,
                               y: start.y + (end.y - start.y) * progress)
        let velocity = continuous ? (end.x - start.x) / span : 0
        return .init(position: position, clickAge: time - latestClicks[lower],
                     rotation: request.style.smoothed ? min(0.12, max(-0.12, velocity * 0.06)) : 0)
    }
}

enum CursorPresentationRenderer {
    private static let images: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 256
        cache.totalCostLimit = 16 * 1_024 * 1_024
        return cache
    }()

    struct Request {
        let sample: CursorPresentationSample
        let style: CursorPresentationStyle
        let sourceFrame: CGRect
    }

    struct Sprite {
        let image: CGImage
        let frame: CGRect
    }

    static func sprite(_ request: Request) -> Sprite? {
        let age = request.sample.clickAge
        let animatedAge = request.style.emphasizesClicks && age >= 0 && age < 0.4 ? age : -1
        let key = "\(request.sample.rotation.bitPattern)|\(animatedAge.bitPattern)" as NSString
        let image: CGImage
        if let cached = images.object(forKey: key) {
            image = cached
        } else {
            guard let rendered = render(request) else { return nil }
            images.setObject(rendered, forKey: key, cost: rendered.bytesPerRow * rendered.height)
            image = rendered
        }
        let scale = request.style.scale.isFinite ? min(3, max(0.75, request.style.scale)) : 1.5
        let size = request.sourceFrame.height * 0.065 * scale
        return .init(image: image, frame: CGRect(
            x: request.sourceFrame.minX + request.sample.position.x * request.sourceFrame.width - size / 2,
            y: request.sourceFrame.minY + request.sample.position.y * request.sourceFrame.height - size / 2,
            width: size, height: size))
    }

    private static func render(_ request: Request) -> CGImage? {
        let pixelSize = 128
        guard let context = CGContext(data: nil, width: pixelSize, height: pixelSize, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 64, y: 64)
        context.scaleBy(x: 1, y: -1)
        let age = request.sample.clickAge
        if request.style.emphasizesClicks, age >= 0, age < 0.4 {
            let progress = age / 0.4
            let radius = 9 + progress * 32
            context.setStrokeColor(CGColor(red: 0.36, green: 0.96, blue: 0.79, alpha: (1 - progress) * 0.65))
            context.setLineWidth(2)
            context.strokeEllipse(in: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
        }
        context.rotate(by: request.sample.rotation)
        let bounce = request.style.emphasizesClicks && age >= 0 && age < 0.3
            ? 1 - 0.16 * sin(min(1, age / 0.3) * .pi) : 1
        context.scaleBy(x: bounce, y: bounce)
        let arrow = CGMutablePath()
        arrow.move(to: .zero)
        for point in [CGPoint(x: 0, y: 31), CGPoint(x: 8, y: 24), CGPoint(x: 14, y: 38),
                      CGPoint(x: 20, y: 35), CGPoint(x: 14, y: 22), CGPoint(x: 25, y: 22)] {
            arrow.addLine(to: point)
        }
        arrow.closeSubpath()
        context.setShadow(offset: CGSize(width: 0, height: 2), blur: 3, color: CGColor(gray: 0, alpha: 0.4))
        context.setFillColor(CGColor(gray: 0.06, alpha: 1))
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.setLineWidth(2.2)
        context.setLineJoin(.round)
        context.addPath(arrow)
        context.drawPath(using: .fillStroke)
        return context.makeImage()
    }

    struct CompositeRequest {
        let image: CIImage
        let sample: CursorPresentationSample
        let style: CursorPresentationStyle
    }

    static func composite(_ request: CompositeRequest) -> CIImage {
        let extent = request.image.extent
        guard let sprite = sprite(.init(sample: request.sample, style: request.style,
            sourceFrame: CGRect(origin: .zero, size: extent.size))) else { return request.image }
        let image = CIImage(cgImage: sprite.image).transformed(by: CGAffineTransform(
            scaleX: sprite.frame.width / CGFloat(sprite.image.width),
            y: sprite.frame.height / CGFloat(sprite.image.height)))
            .transformed(by: CGAffineTransform(translationX: extent.minX + sprite.frame.minX,
                                               y: extent.maxY - sprite.frame.maxY))
        return image.composited(over: request.image).cropped(to: extent)
    }
}

enum CameraZoomMotion {
    struct Request {
        let scene: RecordingScene
        let zoom: ScreenZoomSample
        let intensity: Double
    }

    static func scene(_ request: Request) -> RecordingScene {
        var scene = request.scene
        let frame = scene.sceneLayout.cameraFrame
        let screen = scene.sceneLayout.screenFrame.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard scene.enabledSources.contains(.screen), scene.enabledSources.contains(.camera),
              scene.sceneLayout.layerOrder.last == .camera, screen.contains(frame),
              frame.width * frame.height < screen.width * screen.height * 0.5 else { return scene }
        let fullAmount = ScreenZoomTrack.amount(forMagnification: request.intensity)
        guard fullAmount > 0 else { return scene }
        let progress = min(1, max(0, request.zoom.amount / fullAmount))
        guard progress > 0 else { return scene }
        let scale = 1 - 0.25 * progress
        let width = frame.width * scale
        let height = frame.height * scale
        scene.sceneLayout.cameraFrame = CGRect(
            x: frame.midX < 0.5 ? frame.minX : frame.maxX - width,
            y: frame.midY < 0.5 ? frame.minY : frame.maxY - height,
            width: width, height: height)
        return scene
    }
}

import Foundation

/// Normalized 0...1 rectangle in canvas space. Origin is top-left.
public struct NormalizedRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public static let full = NormalizedRect(x: 0, y: 0, width: 1, height: 1)
    public static let cameraPip = NormalizedRect(x: 0.68, y: 0.68, width: 0.28, height: 0.28)

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public func pixelRect(canvasWidth: Int, canvasHeight: Int) -> PixelRect {
        let width = max(1, canvasWidth)
        let height = max(1, canvasHeight)
        let px = Int((x * Double(width)).rounded())
        let py = Int((y * Double(height)).rounded())
        var pw = Int((self.width * Double(width)).rounded())
        var ph = Int((self.height * Double(height)).rounded())
        pw = max(2, pw & ~1)
        ph = max(2, ph & ~1)
        return PixelRect(
            x: min(max(0, px), width - 2),
            y: min(max(0, py), height - 2),
            width: min(pw, width - min(max(0, px), width - 2)),
            height: min(ph, height - min(max(0, py), height - 2))
        )
    }
}

public struct PixelRect: Equatable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct PortableSceneLayout: Codable, Equatable, Sendable {
    public var canvasWidth: Int
    public var canvasHeight: Int
    public var screen: NormalizedRect
    public var camera: NormalizedRect?

    public static let defaultCanvasWidth = 1920
    public static let defaultCanvasHeight = 1080

    public static let screenOnly = PortableSceneLayout(
        canvasWidth: defaultCanvasWidth,
        canvasHeight: defaultCanvasHeight,
        screen: .full,
        camera: nil
    )

    public static let screenWithCameraPip = PortableSceneLayout(
        canvasWidth: defaultCanvasWidth,
        canvasHeight: defaultCanvasHeight,
        screen: .full,
        camera: .cameraPip
    )

    public static let `default` = screenOnly

    public init(
        canvasWidth: Int = PortableSceneLayout.defaultCanvasWidth,
        canvasHeight: Int = PortableSceneLayout.defaultCanvasHeight,
        screen: NormalizedRect = .full,
        camera: NormalizedRect? = nil
    ) {
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.screen = screen
        self.camera = camera
    }

    public func screenPixels(width: Int? = nil, height: Int? = nil) -> PixelRect {
        screen.pixelRect(
            canvasWidth: width ?? canvasWidth,
            canvasHeight: height ?? canvasHeight
        )
    }

    public func cameraPixels(width: Int? = nil, height: Int? = nil) -> PixelRect? {
        camera?.pixelRect(
            canvasWidth: width ?? canvasWidth,
            canvasHeight: height ?? canvasHeight
        )
    }
}

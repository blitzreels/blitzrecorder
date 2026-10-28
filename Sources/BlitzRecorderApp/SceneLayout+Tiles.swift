import CoreGraphics

/// Space around and between the tiles of a two-camera scene, as a fraction of the canvas width (the same on every
/// side). The background shows through it.
enum SceneTileSpacing: CaseIterable {
    case none, small, medium, large

    var value: CGFloat {
        switch self {
        case .none: 0
        case .small: 0.02
        case .medium: 0.04
        case .large: 0.07
        }
    }

    var title: String {
        switch self {
        case .none: "None"
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }
}

/// The shape both camera tiles share. A narrower shape trims the sides of each picture so the tiles grow taller,
/// and with the screen the screen takes the room the cameras give up.
enum SceneTileShape: Hashable {
    /// The camera's own shape: the whole picture, nothing trimmed.
    case source
    case ratio(CGFloat)
    /// Each tile takes all its space; the picture is trimmed to it.
    case fill

    static let classic = SceneTileShape.ratio(4.0 / 3.0)
    static let square = SceneTileShape.ratio(1)
    static let portrait = SceneTileShape.ratio(4.0 / 5.0)

    /// The shapes offered for a camera, without a ratio that repeats the camera's own.
    static func options(cameraAspectRatio: CGFloat) -> [SceneTileShape] {
        [.source] + [classic, square, portrait].filter {
            guard case .ratio(let ratio) = $0 else { return true }
            return abs(ratio - cameraAspectRatio) > 0.02
        } + [.fill]
    }

    func aspectRatio(cameraAspectRatio: CGFloat) -> CGFloat? {
        switch self {
        case .source: cameraAspectRatio
        case .ratio(let ratio): ratio
        case .fill: nil
        }
    }
}

/// A two-camera scene laid out as even tiles.
struct SceneTiles: Equatable {
    var spacing: SceneTileSpacing
    var shape: SceneTileShape

    /// Shorts fill their tiles edge to edge; wider formats keep each camera's whole picture with a little space.
    static func defaults(for layout: CaptureLayout) -> SceneTiles {
        layout == .vertical ? .init(spacing: .none, shape: .fill) : .init(spacing: .small, shape: .source)
    }

    static func all(cameraAspectRatio: CGFloat) -> [SceneTiles] {
        SceneTileSpacing.allCases.flatMap { spacing in
            SceneTileShape.options(cameraAspectRatio: cameraAspectRatio).map { SceneTiles(spacing: spacing, shape: $0) }
        }
    }
}

extension SceneLayout {
    struct TiledLayoutRequest {
        let tiles: SceneTiles
        let includesScreen: Bool
        let layout: CaptureLayout
        let screenAspectRatio: CGFloat
        let cameraAspectRatio: CGFloat
    }

    /// Two cameras sit side by side or stacked, whichever gives them the most room. With the screen: on wide
    /// canvases the cameras stack beside it, matching its height; on square ones they sit side by side under it;
    /// on vertical ones the screen and both cameras stack in one column. The screen always keeps its whole picture.
    static func tiledLayout(_ request: TiledLayoutRequest) -> SceneLayout {
        let canvas = TileCanvas(aspectRatio: request.layout.aspectRatio, spacing: request.tiles.spacing.value)
        let cameraShape = request.tiles.shape.aspectRatio(cameraAspectRatio: request.cameraAspectRatio)
        let screenShape = request.screenAspectRatio > 0 ? request.screenAspectRatio : defaultScreenAspectRatio
        let rects: (screen: CGRect?, cameras: [CGRect])
        if !request.includesScreen {
            rects = (nil, canvas.bestStack(.init(area: canvas.area, shape: cameraShape,
                                                 cameraAspectRatio: request.cameraAspectRatio)))
        } else if request.layout == .horizontal {
            rects = canvas.screenBesideCameras(screenShape: screenShape, cameraShape: cameraShape)
        } else {
            rects = canvas.screenAboveCameras(.init(
                screenShape: screenShape,
                cameraShape: cameraShape,
                camerasAxis: request.layout == .vertical ? .vertical : .horizontal
            ))
        }
        var sceneLayout = SceneLayout()
        sceneLayout.layerOrder = [.screen, .camera]
        if let screen = rects.screen {
            sceneLayout.screenFrame = canvas.normalized(screen)
        }
        sceneLayout.cameraFrame = canvas.normalized(rects.cameras[0])
        sceneLayout.secondCameraFrame = canvas.normalized(rects.cameras[1])
        return sceneLayout
    }

    struct TilesMatchRequest {
        let includesScreen: Bool
        let layout: CaptureLayout
        let screenAspectRatio: CGFloat
        let cameraAspectRatio: CGFloat
    }

    /// The tiles this layout was made with, or nil once a tile was moved or resized by hand.
    func matchingTiles(_ request: TilesMatchRequest) -> SceneTiles? {
        guard let secondCameraFrame else { return nil }
        return SceneTiles.all(cameraAspectRatio: request.cameraAspectRatio).first { tiles in
            let candidate = Self.tiledLayout(.init(
                tiles: tiles,
                includesScreen: request.includesScreen,
                layout: request.layout,
                screenAspectRatio: request.screenAspectRatio,
                cameraAspectRatio: request.cameraAspectRatio
            ))
            return cameraFrame.isTileMatch(candidate.cameraFrame)
                && secondCameraFrame.isTileMatch(candidate.secondCameraFrame ?? .zero)
                && (!request.includesScreen || screenFrame.isTileMatch(candidate.screenFrame))
        }
    }
}

private extension CGRect {
    var area: CGFloat { width * height }

    func isTileMatch(_ other: CGRect) -> Bool {
        abs(minX - other.minX) < 0.004 && abs(minY - other.minY) < 0.004
            && abs(width - other.width) < 0.004 && abs(height - other.height) < 0.004
    }
}

/// Tile geometry in canvas points: height 1, width the canvas aspect ratio, lower-left origin, so every shape and
/// gap reads the same in any format.
private struct TileCanvas {
    let aspectRatio: CGFloat
    let gap: CGFloat

    init(aspectRatio: CGFloat, spacing: CGFloat) {
        self.aspectRatio = aspectRatio
        gap = spacing * aspectRatio
    }

    var area: CGRect {
        CGRect(x: gap, y: gap, width: max(0.01, aspectRatio - gap * 2), height: max(0.01, 1 - gap * 2))
    }

    func normalized(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX / aspectRatio, y: rect.minY, width: rect.width / aspectRatio, height: rect.height)
    }

    enum Axis { case horizontal, vertical }

    struct StackRequest {
        let area: CGRect
        let shape: CGFloat?
        let cameraAspectRatio: CGFloat
    }

    /// Two tiles across or stacked: the larger tiles for a shape, the least-trimmed picture for Fill.
    func bestStack(_ request: StackRequest) -> [CGRect] {
        let across = stack(.init(area: request.area, shape: request.shape, axis: .horizontal))
        let stacked = stack(.init(area: request.area, shape: request.shape, axis: .vertical))
        guard request.shape == nil else {
            return stacked[0].area > across[0].area + 0.0001 ? stacked : across
        }
        func trim(_ tile: CGRect) -> CGFloat { abs(log(tile.width / max(tile.height, 0.0001) / request.cameraAspectRatio)) }
        return trim(stacked[0]) < trim(across[0]) ? stacked : across
    }

    struct AxisStackRequest {
        let area: CGRect
        let shape: CGFloat?
        let axis: Axis
    }

    /// Two equal tiles along an axis, a gap apart, kept together in the middle of the area.
    func stack(_ request: AxisStackRequest) -> [CGRect] {
        let area = request.area
        let slot = request.axis == .horizontal
            ? CGSize(width: max(0.001, (area.width - gap) / 2), height: area.height)
            : CGSize(width: area.width, height: max(0.001, (area.height - gap) / 2))
        let tile = request.shape.map { slot.fitting(aspectRatio: $0) } ?? slot
        if request.axis == .horizontal {
            let x = area.midX - (tile.width * 2 + gap) / 2
            let y = area.midY - tile.height / 2
            return [CGRect(x: x, y: y, width: tile.width, height: tile.height),
                    CGRect(x: x + tile.width + gap, y: y, width: tile.width, height: tile.height)]
        }
        let x = area.midX - tile.width / 2
        let top = area.midY + (tile.height * 2 + gap) / 2
        return [CGRect(x: x, y: top - tile.height, width: tile.width, height: tile.height),
                CGRect(x: x, y: top - tile.height * 2 - gap, width: tile.width, height: tile.height)]
    }

    /// Fill's camera column on wide canvases: the width the side-by-side layouts give a camera.
    private static let fillColumnShare: CGFloat = 0.3

    /// The screen on the left and the cameras stacked on the right, both as tall as the screen, centred together.
    func screenBesideCameras(screenShape: CGFloat, cameraShape: CGFloat?) -> (screen: CGRect?, cameras: [CGRect]) {
        let area = self.area
        var height: CGFloat
        if let cameraShape {
            height = (area.width - gap + gap * cameraShape / 2) / (screenShape + cameraShape / 2)
        } else {
            height = (area.width - gap - aspectRatio * Self.fillColumnShare) / screenShape
        }
        height = min(area.height, max(0.05, height))
        let tileHeight = max(0.001, (height - gap) / 2)
        let columnWidth = cameraShape.map { tileHeight * $0 } ?? aspectRatio * Self.fillColumnShare
        let screenWidth = height * screenShape
        let x = area.midX - (screenWidth + gap + columnWidth) / 2
        let y = area.midY - height / 2
        let column = CGRect(x: x + screenWidth + gap, y: y, width: columnWidth, height: height)
        return (CGRect(x: x, y: y, width: screenWidth, height: height),
                stack(.init(area: column, shape: nil, axis: .vertical)))
    }

    struct ScreenAboveRequest {
        let screenShape: CGFloat
        let cameraShape: CGFloat?
        let camerasAxis: Axis
    }

    /// The screen across the top, at most half the height on vertical canvases (60% on square ones), and the
    /// cameras under it, the whole group centred.
    func screenAboveCameras(_ request: ScreenAboveRequest) -> (screen: CGRect?, cameras: [CGRect]) {
        let area = self.area
        let maximumShare: CGFloat = request.camerasAxis == .vertical ? 0.5 : 0.6
        let screen = CGSize(width: area.width, height: area.height * maximumShare).fitting(aspectRatio: request.screenShape)
        let below = CGRect(x: area.minX, y: area.minY, width: area.width,
                           height: max(0.001, area.height - screen.height - gap))
        let cameras = stack(.init(area: below, shape: request.cameraShape, axis: request.camerasAxis))
        let camerasBottom = cameras.map(\.minY).min() ?? below.minY
        let camerasHeight = (cameras.map(\.maxY).max() ?? below.maxY) - camerasBottom
        let groupBottom = area.midY - (screen.height + gap + camerasHeight) / 2
        let screenRect = CGRect(x: area.midX - screen.width / 2, y: groupBottom + camerasHeight + gap,
                                width: screen.width, height: screen.height)
        return (screenRect, cameras.map { $0.offsetBy(dx: 0, dy: groupBottom - camerasBottom) })
    }
}

private extension CGSize {
    func fitting(aspectRatio: CGFloat) -> CGSize {
        guard aspectRatio > 0 else { return self }
        let fittedWidth = min(width, height * aspectRatio)
        return CGSize(width: fittedWidth, height: fittedWidth / aspectRatio)
    }
}

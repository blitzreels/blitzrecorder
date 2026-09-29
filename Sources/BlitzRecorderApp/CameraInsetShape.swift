import CoreGraphics

enum CameraInsetAlignment: String, CaseIterable {
    case bottomLeft
    case bottomRight

    var displayName: String {
        switch self {
        case .bottomLeft:
            return "Left"
        case .bottomRight:
            return "Right"
        }
    }

    var symbolName: String {
        switch self {
        case .bottomLeft:
            return "arrow.down.left"
        case .bottomRight:
            return "arrow.down.right"
        }
    }
}

enum CameraInsetShape: String, CaseIterable {
    case landscape
    case portrait
    case circle

    var displayName: String {
        switch self {
        case .landscape:
            return "Wide"
        case .portrait:
            return "Tall"
        case .circle:
            return "Round"
        }
    }

    var symbolName: String {
        switch self {
        case .landscape:
            return "rectangle"
        case .portrait:
            return "rectangle.portrait"
        case .circle:
            return "circle"
        }
    }

    var aspectRatio: CGFloat {
        switch self {
        case .landscape:
            return 16.0 / 9.0
        case .portrait:
            return 9.0 / 16.0
        case .circle:
            return 1
        }
    }

    var cameraMask: SceneCameraMask {
        self == .circle ? .circle : .rectangle
    }

    func aspectRatio(forSource sourceAspectRatio: CGFloat) -> CGFloat {
        guard sourceAspectRatio > 0 else { return aspectRatio }
        switch self {
        case .landscape:
            return max(sourceAspectRatio, 1 / sourceAspectRatio)
        case .portrait:
            return min(sourceAspectRatio, 1 / sourceAspectRatio)
        case .circle:
            return aspectRatio
        }
    }
}

enum SceneCameraMask: String, Codable {
    case rectangle
    case circle

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = SceneCameraMask(rawValue: value) ?? .rectangle
    }
}

enum CameraContentMode: String, CaseIterable, Codable {
    case fill
    case fit

    var displayName: String {
        switch self {
        case .fill:
            return "Fill"
        case .fit:
            return "Fit"
        }
    }

    var symbolName: String {
        switch self {
        case .fill:
            return "arrow.up.left.and.arrow.down.right"
        case .fit:
            return "rectangle"
        }
    }

    var renderContentMode: VideoRenderContentMode {
        switch self {
        case .fill:
            return .aspectFill
        case .fit:
            return .aspectFit
        }
    }
}

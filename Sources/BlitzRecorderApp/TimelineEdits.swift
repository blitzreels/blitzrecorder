import CoreGraphics
import Foundation

enum SilenceClassification: String, Codable, Equatable, Sendable {
    case sound
    case silence
}

struct SilenceOverride: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var start: TimeInterval
    var end: TimeInterval
    let classification: SilenceClassification
}

enum TextOverlayPreset: String, Codable, CaseIterable, Equatable, Sendable {
    case title
    case caption
    case lowerThird

    var displayName: String {
        switch self {
        case .title: return "Title"
        case .caption: return "Caption"
        case .lowerThird: return "Lower third"
        }
    }
}

enum TextOverlayWeight: String, Codable, CaseIterable, Equatable, Sendable {
    case regular
    case semibold
    case bold
    case black
}

enum TextOverlayBackground: String, Codable, CaseIterable, Equatable, Sendable {
    case none
    case pill
    case bar
}

enum TextOverlayAlignment: String, Codable, CaseIterable, Equatable, Sendable {
    case leading
    case center
    case trailing
}

struct TextOverlayStyle: Equatable, Sendable {
    var preset: TextOverlayPreset
    var size: Double
    var weight: TextOverlayWeight
    var colorHex: String
    var background: TextOverlayBackground
    var alignment: TextOverlayAlignment

    static let title = TextOverlayStyle(
        preset: .title,
        size: 0.09,
        weight: .black,
        colorHex: "#FFFFFF",
        background: .none,
        alignment: .center
    )

    static let caption = TextOverlayStyle(
        preset: .caption,
        size: 0.05,
        weight: .bold,
        colorHex: "#FFFFFF",
        background: .pill,
        alignment: .center
    )

    static let lowerThird = TextOverlayStyle(
        preset: .lowerThird,
        size: 0.045,
        weight: .semibold,
        colorHex: "#FFFFFF",
        background: .bar,
        alignment: .leading
    )

    static func preset(_ preset: TextOverlayPreset) -> TextOverlayStyle {
        switch preset {
        case .title: return .title
        case .caption: return .caption
        case .lowerThird: return .lowerThird
        }
    }
}

struct TextOverlay: Equatable, Identifiable, Sendable {
    let id: UUID
    var start: TimeInterval
    var end: TimeInterval
    var text: String
    var frame: CGRect
    var style: TextOverlayStyle
    var fadeSeconds: TimeInterval

    init(
        id: UUID = UUID(),
        start: TimeInterval,
        end: TimeInterval,
        text: String,
        frame: CGRect,
        style: TextOverlayStyle,
        fadeSeconds: TimeInterval = 0.25
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.frame = frame
        self.style = style
        self.fadeSeconds = fadeSeconds
    }

    var duration: TimeInterval {
        max(0, end - start)
    }

    func isVisible(at takeTime: TimeInterval) -> Bool {
        takeTime >= start && takeTime < end
    }

    func opacity(at takeTime: TimeInterval) -> CGFloat {
        guard isVisible(at: takeTime) else { return 0 }
        let fade = min(max(0, fadeSeconds), duration / 2)
        guard fade > 0 else { return 1 }
        let fadeIn = min(1, (takeTime - start) / fade)
        let fadeOut = min(1, (end - takeTime) / fade)
        return CGFloat(max(0, min(fadeIn, fadeOut)))
    }

    static func defaultFrame(for preset: TextOverlayPreset) -> CGRect {
        switch preset {
        case .title: return CGRect(x: 0.1, y: 0.12, width: 0.8, height: 0.2)
        case .caption: return CGRect(x: 0.15, y: 0.78, width: 0.7, height: 0.12)
        case .lowerThird: return CGRect(x: 0.06, y: 0.8, width: 0.6, height: 0.1)
        }
    }
}

enum ScreenZoomEasing: String, Codable, CaseIterable, Equatable, Sendable {
    case linear
    case easeInOut

    func progress(_ value: Double) -> Double {
        let clamped = min(1, max(0, value))
        switch self {
        case .linear:
            return clamped
        case .easeInOut:
            return clamped * clamped * (3 - 2 * clamped)
        }
    }
}

struct ScreenZoomKeyframe: Equatable, Identifiable, Sendable {
    let id: UUID
    var time: TimeInterval
    var amount: Double
    var position: CGPoint
    var easing: ScreenZoomEasing

    init(
        id: UUID = UUID(),
        time: TimeInterval,
        amount: Double,
        position: CGPoint,
        easing: ScreenZoomEasing = .easeInOut
    ) {
        self.id = id
        self.time = time
        self.amount = amount
        self.position = position
        self.easing = easing
    }
}

struct ScreenZoomSample: Equatable, Sendable {
    let amount: CGFloat
    let position: CGPoint

    static let none = ScreenZoomSample(amount: 0, position: .zero)

    var isActive: Bool {
        amount > 0.001
    }
}

struct ScreenZoomTrack: Equatable, Sendable {
    static let maximumAmount = 0.75

    var keyframes: [ScreenZoomKeyframe]
    var generatedFromCursor: Bool
    var intensity: Double
    var isEnabled: Bool = true

    static let empty = ScreenZoomTrack(keyframes: [], generatedFromCursor: false, intensity: 2)

    init(keyframes: [ScreenZoomKeyframe], generatedFromCursor: Bool, intensity: Double) {
        self.keyframes = keyframes.sorted { $0.time < $1.time }
        self.generatedFromCursor = generatedFromCursor
        self.intensity = intensity
    }

    var isEmpty: Bool {
        keyframes.isEmpty
    }

    var isActive: Bool {
        isEnabled && !isEmpty
    }

    static func amount(forMagnification magnification: Double) -> Double {
        guard magnification > 1 else { return 0 }
        return min(maximumAmount, max(0, 1 - 1 / magnification))
    }

    static func magnification(forAmount amount: Double) -> Double {
        let clamped = min(maximumAmount, max(0, amount))
        return 1 / max(0.001, 1 - clamped)
    }

    func sample(at takeTime: TimeInterval) -> ScreenZoomSample {
        guard isEnabled, let first = keyframes.first else { return .none }
        if takeTime <= first.time {
            return ScreenZoomSample(amount: CGFloat(first.amount), position: first.position)
        }
        guard let last = keyframes.last, takeTime < last.time else {
            let keyframe = keyframes[keyframes.count - 1]
            return ScreenZoomSample(amount: CGFloat(keyframe.amount), position: keyframe.position)
        }
        var lowerIndex = 0
        var upperIndex = keyframes.count - 1
        while upperIndex - lowerIndex > 1 {
            let middle = (lowerIndex + upperIndex) / 2
            if keyframes[middle].time <= takeTime {
                lowerIndex = middle
            } else {
                upperIndex = middle
            }
        }
        let from = keyframes[lowerIndex]
        let to = keyframes[upperIndex]
        let span = to.time - from.time
        guard span > 0.0001 else {
            return ScreenZoomSample(amount: CGFloat(to.amount), position: to.position)
        }
        let progress = to.easing.progress((takeTime - from.time) / span)
        let amount = from.amount + (to.amount - from.amount) * progress
        let position = CGPoint(
            x: from.position.x + (to.position.x - from.position.x) * progress,
            y: from.position.y + (to.position.y - from.position.y) * progress
        )
        return ScreenZoomSample(amount: CGFloat(amount), position: position)
    }

    func hasVariation(in range: ClosedRange<TimeInterval>) -> Bool {
        guard isActive else { return false }
        let start = sample(at: range.lowerBound)
        let end = sample(at: range.upperBound)
        if start != end { return true }
        return keyframes.contains { $0.time > range.lowerBound && $0.time < range.upperBound }
    }

    var keyframeTimes: [TimeInterval] {
        isEnabled ? keyframes.map(\.time) : []
    }
}

struct TimelineEdits: Equatable, Sendable {
    var cuts: [TimelineCut]
    var textOverlays: [TextOverlay]
    var zoom: ScreenZoomTrack
    var silenceOverrides: [SilenceOverride] = []
    var cursorStyle: CursorPresentationStyle = .standard
    var cameraFollowsZoom: Bool = false
    var privacyMasks: [PrivacyMask] = []
    var outputVariants: [RecordingOutputVariant] = []
    var activeOutputLayout: CaptureLayout?
    var voiceCleanup: VoiceCleanupSettings = .disabled
    var videoSplits: [Double] = []
    var silenceRemovalApplied: Bool = false

    static let empty = TimelineEdits(cuts: [], textOverlays: [], zoom: .empty)

    var enabledCuts: [TimelineCut] {
        cuts.filter(\.isEnabled)
    }
}

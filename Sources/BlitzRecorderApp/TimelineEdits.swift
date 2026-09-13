import CoreGraphics
import CoreMedia
import Foundation

enum TimelineCutKind: String, Codable, Equatable, Sendable {
    case silence
    case manual
}

enum TimelineCutSource: String, Codable, Equatable, Sendable {
    case automatic = "auto"
    case user
}

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

struct TimelineCut: Equatable, Identifiable, Sendable {
    let id: UUID
    var start: TimeInterval
    var end: TimeInterval
    var kind: TimelineCutKind
    var source: TimelineCutSource
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        start: TimeInterval,
        end: TimeInterval,
        kind: TimelineCutKind,
        source: TimelineCutSource,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.kind = kind
        self.source = source
        self.isEnabled = isEnabled
    }

    var duration: TimeInterval {
        max(0, end - start)
    }
}

struct TimelineMediaInsertion: Equatable {
    let sourceStart: CMTime
    let compositionStart: CMTime
    let duration: CMTime

    static func == (lhs: TimelineMediaInsertion, rhs: TimelineMediaInsertion) -> Bool {
        CMTimeCompare(lhs.sourceStart, rhs.sourceStart) == 0
            && CMTimeCompare(lhs.compositionStart, rhs.compositionStart) == 0
            && CMTimeCompare(lhs.duration, rhs.duration) == 0
    }
}

struct TimelineMediaInsertionRequest {
    let activeTakeStart: CMTime
    let sourceTimeAtActiveStart: CMTime
    let sourceEnd: CMTime
}

struct TimelineTimeMap: Equatable {
    static let timescale: CMTimeScale = 600

    struct KeptRange: Equatable {
        let takeStart: CMTime
        let takeEnd: CMTime
        let outputStart: CMTime

        var duration: CMTime {
            CMTimeSubtract(takeEnd, takeStart)
        }

        var outputEnd: CMTime {
            CMTimeAdd(outputStart, duration)
        }

        static func == (lhs: KeptRange, rhs: KeptRange) -> Bool {
            CMTimeCompare(lhs.takeStart, rhs.takeStart) == 0
                && CMTimeCompare(lhs.takeEnd, rhs.takeEnd) == 0
                && CMTimeCompare(lhs.outputStart, rhs.outputStart) == 0
        }
    }

    struct RemovedRange: Equatable {
        let start: TimeInterval
        let end: TimeInterval
        let cutIDs: [UUID]

        var duration: TimeInterval {
            max(0, end - start)
        }
    }

    struct Seam: Equatable {
        let outputTime: TimeInterval
        let takeStart: TimeInterval
        let takeEnd: TimeInterval
        let cutIDs: [UUID]

        var removedDuration: TimeInterval {
            max(0, takeEnd - takeStart)
        }
    }

    let takeDuration: CMTime
    let keptRanges: [KeptRange]
    let removedRanges: [RemovedRange]

    static func == (lhs: TimelineTimeMap, rhs: TimelineTimeMap) -> Bool {
        CMTimeCompare(lhs.takeDuration, rhs.takeDuration) == 0
            && lhs.keptRanges == rhs.keptRanges
            && lhs.removedRanges == rhs.removedRanges
    }

    init(takeDuration: CMTime, cuts: [TimelineCut]) {
        let normalizedDuration = CMTimeMaximum(
            .zero,
            CMTimeConvertScale(takeDuration, timescale: Self.timescale, method: .roundHalfAwayFromZero)
        )
        self.takeDuration = normalizedDuration
        let durationSeconds = normalizedDuration.seconds

        var removed: [RemovedRange] = []
        let candidates = cuts
            .filter { $0.isEnabled && $0.start.isFinite && $0.end.isFinite }
            .map { cut -> (start: TimeInterval, end: TimeInterval, id: UUID) in
                let start = min(max(0, cut.start), durationSeconds)
                let end = min(max(start, cut.end), durationSeconds)
                return (start, end, cut.id)
            }
            .filter { $0.end - $0.start > 1.0 / Double(Self.timescale) }
            .sorted { $0.start < $1.start }
        for candidate in candidates {
            if let last = removed.last, candidate.start <= last.end + 1.0 / Double(Self.timescale) {
                removed[removed.count - 1] = RemovedRange(
                    start: last.start,
                    end: max(last.end, candidate.end),
                    cutIDs: last.cutIDs + [candidate.id]
                )
            } else {
                removed.append(RemovedRange(start: candidate.start, end: candidate.end, cutIDs: [candidate.id]))
            }
        }
        self.removedRanges = removed

        var kept: [KeptRange] = []
        var cursor = CMTime.zero
        var outputCursor = CMTime.zero
        for range in removed {
            let removedStart = Self.time(range.start)
            let removedEnd = Self.time(range.end)
            if CMTimeCompare(removedStart, cursor) > 0 {
                let keptRange = KeptRange(takeStart: cursor, takeEnd: removedStart, outputStart: outputCursor)
                kept.append(keptRange)
                outputCursor = keptRange.outputEnd
            }
            cursor = CMTimeMaximum(cursor, removedEnd)
        }
        if CMTimeCompare(normalizedDuration, cursor) > 0 {
            kept.append(KeptRange(takeStart: cursor, takeEnd: normalizedDuration, outputStart: outputCursor))
        }
        self.keptRanges = kept
    }

    static func identity(takeDuration: CMTime) -> TimelineTimeMap {
        TimelineTimeMap(takeDuration: takeDuration, cuts: [])
    }

    var outputDuration: CMTime {
        keptRanges.last?.outputEnd ?? .zero
    }

    var hasCuts: Bool {
        !removedRanges.isEmpty
    }

    var removedDuration: TimeInterval {
        removedRanges.reduce(0) { $0 + $1.duration }
    }

    var seams: [Seam] {
        removedRanges.map { range in
            Seam(
                outputTime: outputSeconds(forTakeSeconds: range.start),
                takeStart: range.start,
                takeEnd: range.end,
                cutIDs: range.cutIDs
            )
        }
    }

    func outputTime(forTake takeTime: CMTime) -> CMTime {
        let time = CMTimeConvertScale(takeTime, timescale: Self.timescale, method: .roundHalfAwayFromZero)
        var lower = 0
        var upper = keptRanges.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if CMTimeCompare(time, keptRanges[middle].takeEnd) < 0 {
                upper = middle
            } else {
                lower = middle + 1
            }
        }
        guard lower < keptRanges.count else { return outputDuration }
        let range = keptRanges[lower]
        guard CMTimeCompare(time, range.takeStart) >= 0 else { return range.outputStart }
        return CMTimeAdd(range.outputStart, CMTimeSubtract(time, range.takeStart))
    }

    func outputSeconds(forTakeSeconds seconds: TimeInterval) -> TimeInterval {
        outputTime(forTake: Self.time(seconds)).seconds
    }

    func takeTime(forOutput outputTime: CMTime) -> CMTime {
        let time = CMTimeConvertScale(outputTime, timescale: Self.timescale, method: .roundHalfAwayFromZero)
        let index = outputRangeIndex(at: time)
        guard index < keptRanges.count else { return keptRanges.last?.takeEnd ?? takeDuration }
        let range = keptRanges[index]
        let offset = CMTimeMaximum(.zero, CMTimeSubtract(time, range.outputStart))
        return CMTimeAdd(range.takeStart, offset)
    }

    func takeSeconds(forOutputSeconds seconds: TimeInterval) -> TimeInterval {
        takeTime(forOutput: Self.time(seconds)).seconds
    }

    func isRemoved(takeTime seconds: TimeInterval) -> Bool {
        removedRange(containing: seconds) != nil
    }

    func removedRange(containing seconds: TimeInterval) -> RemovedRange? {
        guard seconds.isFinite else { return nil }
        var lower = 0
        var upper = removedRanges.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if seconds < removedRanges[middle].end {
                upper = middle
            } else {
                lower = middle + 1
            }
        }
        guard lower < removedRanges.count, seconds >= removedRanges[lower].start else { return nil }
        return removedRanges[lower]
    }

    func keptRange(containingOutput outputTime: CMTime) -> KeptRange? {
        let index = outputRangeIndex(at: outputTime)
        guard index < keptRanges.count,
              CMTimeCompare(outputTime, keptRanges[index].outputStart) >= 0 else { return nil }
        return keptRanges[index]
    }

    private func outputRangeIndex(at time: CMTime) -> Int {
        var lower = 0
        var upper = keptRanges.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if CMTimeCompare(time, keptRanges[middle].outputEnd) < 0 {
                upper = middle
            } else {
                lower = middle + 1
            }
        }
        return lower
    }

    func mediaInsertions(_ request: TimelineMediaInsertionRequest) -> [TimelineMediaInsertion] {
        let activeStart = CMTimeConvertScale(
            request.activeTakeStart,
            timescale: Self.timescale,
            method: .roundHalfAwayFromZero
        )
        let sourceAtActiveStart = CMTimeConvertScale(
            request.sourceTimeAtActiveStart,
            timescale: Self.timescale,
            method: .roundHalfAwayFromZero
        )
        let sourceEnd = CMTimeConvertScale(request.sourceEnd, timescale: Self.timescale, method: .roundHalfAwayFromZero)
        let availableSource = CMTimeSubtract(sourceEnd, sourceAtActiveStart)
        guard CMTimeCompare(availableSource, .zero) > 0 else { return [] }
        let activeEnd = CMTimeAdd(activeStart, availableSource)

        var insertions: [TimelineMediaInsertion] = []
        for range in keptRanges {
            let pieceStart = CMTimeMaximum(range.takeStart, activeStart)
            let pieceEnd = CMTimeMinimum(range.takeEnd, activeEnd)
            guard CMTimeCompare(pieceEnd, pieceStart) > 0 else { continue }
            let sourceStart = CMTimeAdd(sourceAtActiveStart, CMTimeSubtract(pieceStart, activeStart))
            let compositionStart = CMTimeAdd(range.outputStart, CMTimeSubtract(pieceStart, range.takeStart))
            insertions.append(TimelineMediaInsertion(
                sourceStart: sourceStart,
                compositionStart: compositionStart,
                duration: CMTimeSubtract(pieceEnd, pieceStart)
            ))
        }
        return insertions
    }

    static func time(_ seconds: TimeInterval) -> CMTime {
        guard seconds.isFinite else { return .zero }
        return CMTime(seconds: max(0, seconds), preferredTimescale: timescale)
    }
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

    static let empty = TimelineEdits(cuts: [], textOverlays: [], zoom: .empty)

    var enabledCuts: [TimelineCut] {
        cuts.filter(\.isEnabled)
    }
}

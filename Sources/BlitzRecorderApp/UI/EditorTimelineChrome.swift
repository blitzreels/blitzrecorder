import Observation
import SwiftUI

let timelineContentSpace = "EditorTimelineContent"

@MainActor
@Observable
final class EditorTimelineScrollOffset {
    var value: CGFloat = 0
}

@MainActor
@Observable
final class EditorTimelineRulerHover {
    var position: CGFloat?

    struct Update {
        let location: CGPoint?
        let ruler: CGRect
        let isInteractive: Bool
    }

    func update(_ request: Update) {
        let next = request.location.flatMap { location -> CGFloat? in
            guard request.isInteractive, request.ruler.contains(location) else { return nil }
            return location.x - request.ruler.minX
        }
        if position != next { position = next }
    }
}

struct EditorTimelineHoverLine: View {
    let hover: EditorTimelineRulerHover
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let position = hover.position
        Canvas { context, size in
            guard let position, position >= 0, position <= size.width else { return }
            let x = (position * displayScale).rounded() / displayScale
            context.fill(Path(CGRect(x: x, y: 0, width: 1 / displayScale, height: size.height)),
                         with: .color(BlitzUI.secondaryText))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct EditorTimelinePinnedRuler<Content: View>: View {
    struct Configuration {
        let scrollOffset: EditorTimelineScrollOffset
        let viewportWidth: CGFloat
        let content: Content
    }

    let configuration: Configuration

    var body: some View {
        configuration.content
            .offset(x: -configuration.scrollOffset.value)
            .frame(width: configuration.viewportWidth, alignment: .leading)
            .clipped()
    }
}

struct EditorTimelineTrackDuration {
    struct Request {
        let rawDuration: Double?
        let playbackDuration: Double
    }

    static func resolve(_ request: Request) -> Double {
        let playbackDuration = request.playbackDuration.isFinite
            ? max(0, request.playbackDuration)
            : 0
        guard let rawDuration = request.rawDuration, rawDuration.isFinite else {
            return playbackDuration
        }
        return min(max(0, rawDuration), playbackDuration)
    }
}

struct EditorTimelinePlayhead: View {
    struct Configuration {
        let projection: EditorTimelineProjection
        let scrollOffset: EditorTimelineScrollOffset
        let pixelsPerSecond: CGFloat
        let playbackTime: Double
        let liveTime: () -> Double
        let isPlaying: Bool
        let isInteractive: Bool
        let rulerHeight: CGFloat
        let viewportWidth: CGFloat
        let onSeek: (Double) -> Void
        let onSeekEnded: () -> Void
    }

    let configuration: Configuration
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !configuration.isPlaying)) { _ in
            let time = configuration.isPlaying ? configuration.liveTime() : configuration.playbackTime
            let displayTime = configuration.projection.displayTime(time)
            let rawX = 8 + CGFloat(displayTime) * configuration.pixelsPerSecond - configuration.scrollOffset.value
            let x = (rawX * displayScale).rounded() / displayScale
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    guard x >= 0, x <= size.width else { return }
                    let marker = EditorTimelinePlayheadShape().path(in: CGRect(x: x - 6, y: 0, width: 12, height: size.height))
                    context.stroke(marker, with: .color(.black.opacity(0.7)), lineWidth: 2)
                    context.fill(marker, with: .color(BlitzUI.mint))
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                Color.clear
                    .frame(width: max(0, min(configuration.viewportWidth, x + 14) - max(0, x - 14)),
                        height: configuration.rulerHeight)
                    .contentShape(.rect)
                    .offset(x: max(0, x - 14))
                    .allowsHitTesting(configuration.isInteractive && x >= 0 && x <= configuration.viewportWidth)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("EditorTimelinePlayhead"))
                            .onChanged { value in
                                guard configuration.pixelsPerSecond > 0 else { return }
                                let displayTime = Double((value.location.x + configuration.scrollOffset.value - 8)
                                    / configuration.pixelsPerSecond)
                                configuration.onSeek(configuration.projection.takeTime(
                                    min(configuration.projection.duration, max(0, displayTime))))
                            }
                            .onEnded { _ in configuration.onSeekEnded() },
                        isEnabled: configuration.isInteractive
                    )
                    .accessibilityLabel("Playhead")
                    .accessibilityValue(MediaTimecode.label(.init(time: displayTime, duration: configuration.projection.duration)))
                    .help("Drag to scrub the full timeline")
            }
            .coordinateSpace(name: "EditorTimelinePlayhead")
            .opacity(configuration.isInteractive ? 1 : 0.4)
        }
    }
}

private struct EditorTimelinePlayheadShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius: CGFloat = 2.5
        let shoulder = rect.minY + 8
        let stemTop = rect.minY + 13
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: shoulder))
        path.addLine(to: CGPoint(x: rect.midX + 1, y: stemTop))
        path.addLine(to: CGPoint(x: rect.midX + 1, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX - 1, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX - 1, y: stemTop))
        path.addLine(to: CGPoint(x: rect.minX, y: shoulder))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

import SwiftUI

struct EditorTimelineControlAnchor: Identifiable {
    let id: String
    let bounds: Anchor<CGRect>
    let content: AnyView
}

struct EditorTimelineControlKey: PreferenceKey {
    static let defaultValue: [EditorTimelineControlAnchor] = []

    static func reduce(value: inout [EditorTimelineControlAnchor], nextValue: () -> [EditorTimelineControlAnchor]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    func timelineControl(id: String) -> some View {
        hidden()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .anchorPreference(key: EditorTimelineControlKey.self, value: .bounds) { bounds in
                [.init(id: id, bounds: bounds, content: AnyView(self))]
            }
    }
}

struct EditorTimelineControlLayer: View {
    struct Configuration {
        let controls: [EditorTimelineControlAnchor]
        let geometry: GeometryProxy
        let viewport: CGRect
    }

    let configuration: Configuration

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(configuration.controls) { control in
                let frame = configuration.geometry[control.bounds]
                control.content
                    .allowsHitTesting(true)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX - configuration.viewport.minX, y: frame.midY - configuration.viewport.minY)
                    .accessibilityHidden(!frame.intersects(configuration.viewport))
            }
        }
        .frame(width: configuration.viewport.width, height: configuration.viewport.height,
               alignment: .topLeading)
        .contentShape(hitRegion)
        .clipped()
        .offset(x: configuration.viewport.minX, y: configuration.viewport.minY)
    }

    private var hitRegion: Path {
        Path { path in
            for control in configuration.controls {
                let frame = configuration.geometry[control.bounds].intersection(configuration.viewport)
                guard !frame.isNull, !frame.isEmpty else { continue }
                path.addRect(frame.offsetBy(dx: -configuration.viewport.minX, dy: -configuration.viewport.minY))
            }
        }
    }
}

struct EditorTimelineGrip: View {
    let tint: Color
    let isActive: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(white: isActive ? 0.2 : 0.12))
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(isActive ? BlitzUI.strongStroke : BlitzUI.panelStroke, lineWidth: 1)
            }
            .overlay {
                Capsule()
                    .fill(isActive ? tint : BlitzUI.supportingText)
                    .frame(width: 2, height: 12)
            }
            .frame(width: 8, height: 24)
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }
}

struct EditorTimelineViewport: Equatable {
    struct Request {
        let offset: CGFloat
        let viewportWidth: CGFloat
        let contentWidth: CGFloat
    }

    let lowerBound: CGFloat
    let upperBound: CGFloat

    var width: CGFloat { max(0, upperBound - lowerBound) }

    static func resolve(_ request: Request) -> Self {
        guard request.contentWidth.isFinite, request.contentWidth > 0,
            request.viewportWidth.isFinite, request.viewportWidth > 0
        else {
            return Self(lowerBound: 0, upperBound: 0)
        }
        let offset = request.offset.isFinite ? request.offset : 0
        let start = min(max(0, offset), max(0, request.contentWidth - request.viewportWidth))
        let tile: CGFloat = 128
        return Self(
            lowerBound: max(0, floor(start / tile) * tile - tile),
            upperBound: min(request.contentWidth, ceil((start + request.viewportWidth) / tile) * tile + tile)
        )
    }
}

enum EditorTimelineRangeChrome {
    struct Request {
        let range: EditorTimeRange
        let projection: EditorTimelineProjection
        let pixelsPerSecond: CGFloat
        let height: CGFloat
    }

    static func frame(_ request: Request) -> CGRect {
        let start = CGFloat(request.projection.displayTime(request.range.start)) * request.pixelsPerSecond
        let end = CGFloat(request.projection.displayTime(request.range.end)) * request.pixelsPerSecond
        return CGRect(x: start, y: 0, width: max(1, end - start), height: max(0, request.height))
    }
}

struct EditorTimelineRangeHighlight: View {
    struct Configuration {
        let range: EditorTimeRange
        let projection: EditorTimelineProjection
        let pixelsPerSecond: CGFloat
        let height: CGFloat
        let tint: Color
    }

    let configuration: Configuration

    var body: some View {
        let frame = EditorTimelineRangeChrome.frame(.init(
            range: configuration.range, projection: configuration.projection,
            pixelsPerSecond: configuration.pixelsPerSecond, height: configuration.height))
        Rectangle()
            .fill(BlitzUI.cardFill)
            .overlay { Rectangle().strokeBorder(configuration.tint.opacity(0.85), lineWidth: 1) }
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct EditorTimelineFilmstripCells {
    struct Request {
        let width: CGFloat
        let frameCount: Int
        let viewport: EditorTimelineViewport
    }

    struct Cell {
        let x: CGFloat
        let width: CGFloat
        let frameIndex: Int
    }

    static func visible(_ request: Request) -> [Cell] {
        guard request.width.isFinite, request.width > 0, request.frameCount > 0,
            request.viewport.width > 0
        else { return [] }
        let count = max(1, Int(ceil(request.width / 84)))
        let cellWidth = request.width / CGFloat(count)
        let first = max(0, min(count, Int(floor(request.viewport.lowerBound / cellWidth))))
        let end = max(first, min(count, Int(ceil(request.viewport.upperBound / cellWidth))))
        return (first..<end).map { index in
            let progress = count > 1 ? Double(index) / Double(count - 1) : 0
            return Cell(
                x: CGFloat(index) * cellWidth,
                width: cellWidth,
                frameIndex: min(request.frameCount - 1, Int((progress * Double(request.frameCount - 1)).rounded()))
            )
        }
    }

    static func loadingCount(for width: CGFloat) -> Int {
        let count = EditorFilmstripLayout.requestedFrameCount(width: width)
        return [16, 32, 64, 128, 192].first { $0 >= count } ?? 192
    }
}

struct EditorTimelineMediaCanvas: View, Equatable {
    let frames: [CGImage]
    let waveform: EditorAudioWaveform?
    let isVideo: Bool
    let tint: Color
    let projection: EditorTimelineProjection
    let sourceDuration: Double
    let sourceOffset: Double
    let pixelsPerSecond: CGFloat
    let viewport: EditorTimelineViewport

    @Environment(\.displayScale) private var displayScale

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isVideo == rhs.isVideo && lhs.tint == rhs.tint
            && lhs.projection == rhs.projection && lhs.sourceDuration == rhs.sourceDuration
            && lhs.sourceOffset == rhs.sourceOffset && lhs.pixelsPerSecond == rhs.pixelsPerSecond
            && lhs.viewport == rhs.viewport
            && lhs.waveform === rhs.waveform && lhs.frames.elementsEqual(rhs.frames, by: { $0 === $1 })
    }

    var body: some View {
        Canvas { context, size in
            guard pixelsPerSecond > 0, sourceDuration > 0 else { return }
            let fragments = projection.visibleFragments(
                .init(
                    start: Double(viewport.lowerBound / pixelsPerSecond),
                    end: Double(viewport.upperBound / pixelsPerSecond)
                ))
            if isVideo, !frames.isEmpty {
                let width = CGFloat(projection.duration) * pixelsPerSecond
                for cell in EditorTimelineFilmstripCells.visible(
                    .init(
                        width: width, frameCount: frames.count, viewport: viewport
                    ))
                {
                    let outputTime = Double(cell.x + cell.width / 2) / Double(pixelsPerSecond)
                    let sourceTime = projection.takeTime(outputTime) - sourceOffset
                    guard sourceTime >= 0, sourceTime < sourceDuration else { continue }
                    let frameIndex = min(
                        frames.count - 1,
                        max(
                            0,
                            Int(
                                (sourceTime / sourceDuration * Double(frames.count - 1)).rounded()
                            )))
                    let frame = frames[frameIndex]
                    let rect = CGRect(x: cell.x - viewport.lowerBound, y: 0, width: cell.width, height: size.height)
                    let scale = max(rect.width / CGFloat(frame.width), rect.height / CGFloat(frame.height))
                    let imageSize = CGSize(width: CGFloat(frame.width) * scale, height: CGFloat(frame.height) * scale)
                    var clipped = context
                    clipped.clip(to: Path(rect))
                    clipped.draw(
                        Image(decorative: frame, scale: 1),
                        in: CGRect(
                            x: rect.midX - imageSize.width / 2, y: rect.midY - imageSize.height / 2,
                            width: imageSize.width, height: imageSize.height
                        ))
                }
            }
            var bars = Path()
            for fragment in fragments {
                let sourceStart = max(0, fragment.takeStart - sourceOffset)
                let sourceEnd = min(sourceDuration, fragment.takeEnd - sourceOffset)
                guard sourceEnd > sourceStart else { continue }
                let start = fragment.start + sourceStart + sourceOffset - fragment.takeStart
                let x = CGFloat(start) * pixelsPerSecond
                let endX = x + CGFloat(sourceEnd - sourceStart) * pixelsPerSecond
                if !isVideo {
                    let first = Int(floor(x * displayScale))
                    let end = Int(ceil(endX * displayScale))
                    for index in first..<end {
                        let columnStart = max(x, CGFloat(index) / displayScale)
                        let columnEnd = min(endX, CGFloat(index + 1) / displayScale)
                        let startTime = sourceStart + Double(columnStart - x) / Double(pixelsPerSecond)
                        let endTime = sourceStart + Double(columnEnd - x) / Double(pixelsPerSecond)
                        let amplitude = CGFloat(
                            waveform?.amplitude(
                                .init(
                                    start: startTime / sourceDuration, end: endTime / sourceDuration
                                )) ?? 0)
                        let height = max(1 / displayScale, amplitude * (size.height - 6))
                        bars.addRect(
                            CGRect(
                                x: columnStart - viewport.lowerBound, y: (size.height - height) / 2,
                                width: columnEnd - columnStart, height: height
                            ))
                    }
                }
            }
            if !isVideo { context.fill(bars, with: .color(tint.opacity(0.9))) }
        }
        .frame(width: viewport.width)
        .offset(x: viewport.lowerBound)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

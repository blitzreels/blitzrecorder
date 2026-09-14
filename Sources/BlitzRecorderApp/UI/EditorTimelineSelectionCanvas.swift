import SwiftUI

struct EditorTimelineSelectionCanvas: View {
    struct Configuration {
        let ranges: [EditorTimeRange]
        let projection: EditorTimelineProjection
        let viewport: EditorTimelineViewport
        let pixelsPerSecond: CGFloat
        let height: CGFloat
        let isSilence: Bool
    }

    let configuration: Configuration

    var body: some View {
        Canvas { context, size in
            guard configuration.pixelsPerSecond > 0 else { return }
            let color = configuration.isSilence ? Color.white : BlitzUI.mint
            var start: Int?
            let width = Int(ceil(size.width))
            for pixel in 0...width {
                let time = configuration.projection.takeTime(Double(
                    (configuration.viewport.lowerBound + CGFloat(pixel) + 0.5) / configuration.pixelsPerSecond))
                let selected = pixel < width && contains(time)
                if selected, start == nil { start = pixel }
                if !selected, let first = start {
                    let rect = CGRect(x: first, y: 0, width: pixel - first, height: Int(configuration.height))
                    context.fill(Path(rect), with: .color(color.opacity(0.1)))
                    context.stroke(Path(rect.insetBy(dx: 1, dy: 1)), with: .color(color), lineWidth: 2)
                    start = nil
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func contains(_ time: Double) -> Bool {
        var lower = 0
        var upper = configuration.ranges.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if configuration.ranges[middle].start <= time { lower = middle + 1 } else { upper = middle }
        }
        return lower > 0 && configuration.ranges[lower - 1].end > time
    }
}

import SwiftUI

struct EditorTranscriptLayout: Equatable {
    struct Request {
        let items: [EditorTranscriptItem]
        let projection: EditorTimelineProjection
    }

    struct Item: Equatable {
        let source: EditorTranscriptItem
        let start: Double
        let end: Double
    }

    struct Run: Identifiable, Equatable {
        let item: Item
        let x: CGFloat
        let width: CGFloat
        var id: Int { item.source.id }
    }

    struct Viewport {
        let viewport: EditorTimelineViewport
        let pixelsPerSecond: CGFloat
    }

    let items: [Item]

    init(_ request: Request) {
        items = request.items.compactMap { item in
            let start = request.projection.displayTime(item.range.start)
            let end = request.projection.displayTime(item.range.end)
            return end > start ? Item(source: item, start: start, end: end) : nil
        }
    }

    func item(at time: Double) -> Item? {
        guard time.isFinite else { return nil }
        var lower = 0
        var upper = items.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if items[middle].start <= time { lower = middle + 1 } else { upper = middle }
        }
        guard lower > 0, items[lower - 1].end > time else { return nil }
        return items[lower - 1]
    }

    func runs(_ request: Viewport) -> [Run] {
        guard request.pixelsPerSecond.isFinite, request.pixelsPerSecond > 0,
            request.viewport.width > 0 else { return [] }
        var runs: [Run] = []
        var previousID: Int?
        for pixel in 0..<Int(ceil(request.viewport.width)) {
            let x = request.viewport.lowerBound + CGFloat(pixel) + 0.5
            guard let item = item(at: Double(x / request.pixelsPerSecond)) else {
                previousID = nil
                continue
            }
            guard item.source.id != previousID else { continue }
            previousID = item.source.id
            let start = max(request.viewport.lowerBound, CGFloat(item.start) * request.pixelsPerSecond)
            let end = min(request.viewport.upperBound, CGFloat(item.end) * request.pixelsPerSecond)
            runs.append(.init(item: item, x: start - request.viewport.lowerBound, width: max(1, end - start)))
        }
        return runs
    }
}

struct EditorTimelineRangeClick {
    let range: EditorTimeRange
    let modifiers: NSEvent.ModifierFlags
}

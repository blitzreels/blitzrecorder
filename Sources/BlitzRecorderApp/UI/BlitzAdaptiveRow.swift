import SwiftUI

struct BlitzAdaptiveRow: Layout {
    struct Configuration {
        var minimumContentWidth: CGFloat = 240
        var spacing: CGFloat = 12
    }

    var configuration: Configuration

    init(_ configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(.init(width: proposal.width, subviews: subviews)).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangement(.init(width: bounds.width, subviews: subviews))
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private struct Request {
        let width: CGFloat?
        let subviews: Subviews
    }

    private struct Arrangement {
        let size: CGSize
        let frames: [CGRect]
    }

    private func arrangement(_ request: Request) -> Arrangement {
        let subviews = request.subviews
        guard let content = subviews.first else { return .init(size: .zero, frames: []) }
        let spacing = configuration.spacing
        let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
        let naturalWidth = ideal.reduce(0) { $0 + $1.width } + CGFloat(subviews.count - 1) * spacing
        let width = max(0, request.width.flatMap { $0.isFinite ? $0 : nil } ?? naturalWidth)
        let accessoriesWidth = ideal.dropFirst().reduce(0) { $0 + $1.width }
            + CGFloat(subviews.count - 1) * spacing
        let isHorizontal = subviews.count == 1
            || width >= min(ideal[0].width, configuration.minimumContentWidth) + accessoriesWidth
        let contentWidth = isHorizontal ? max(0, width - accessoriesWidth) : width
        let contentSize = content.sizeThatFits(.init(width: contentWidth, height: nil))
        if isHorizontal {
            let height = max(contentSize.height, ideal.dropFirst().map(\.height).max() ?? 0)
            var frames = [CGRect(x: 0, y: (height - contentSize.height) / 2,
                                 width: contentWidth, height: contentSize.height)]
            var x = contentWidth + spacing
            for size in ideal.dropFirst() {
                frames.append(CGRect(x: x, y: (height - size.height) / 2, width: size.width, height: size.height))
                x += size.width + spacing
            }
            return .init(size: CGSize(width: width, height: height), frames: frames)
        }
        var frames = [CGRect(origin: .zero, size: CGSize(width: width, height: contentSize.height))]
        var x: CGFloat = 0
        var y = contentSize.height + spacing
        var rowHeight: CGFloat = 0
        for index in 1..<subviews.count {
            let size = subviews[index].sizeThatFits(.init(width: min(width, ideal[index].width), height: nil))
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return .init(size: CGSize(width: width, height: y + rowHeight), frames: frames)
    }
}

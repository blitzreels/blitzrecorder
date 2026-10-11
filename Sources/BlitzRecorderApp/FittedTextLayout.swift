import AppKit
import CoreText

struct FittedTextLayout {
    struct Request {
        let text: String
        let fontSize: CGFloat
        let weight: NSFont.Weight
        let color: NSColor
        let alignment: NSTextAlignment
        let bounds: CGSize
    }
    let text: NSAttributedString
    let size: CGSize
    let fontSize: CGFloat

    static func resolve(_ request: Request) -> Self {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = request.alignment
        paragraph.lineBreakMode = .byWordWrapping
        let bounds = CGSize(width: max(1, request.bounds.width), height: max(1, request.bounds.height))
        func layout(_ fontSize: CGFloat) -> Self {
            let text = NSAttributedString(string: request.text, attributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: request.weight),
                .foregroundColor: request.color, .paragraphStyle: paragraph
            ])
            let setter = CTFramesetterCreateWithAttributedString(text)
            let size = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(), nil,
                CGSize(width: bounds.width, height: .greatestFiniteMagnitude), nil)
            return .init(text: text, size: .init(width: bounds.width, height: min(bounds.height, ceil(size.height) + 2)),
                fontSize: fontSize)
        }
        func fits(_ value: Self) -> Bool {
            let setter = CTFramesetterCreateWithAttributedString(value.text)
            let frame = CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: CGRect(origin: .zero, size: bounds), transform: nil), nil)
            return CTFrameGetVisibleStringRange(frame).length == value.text.length
        }
        let desired = max(0.1, request.fontSize)
        let initial = layout(desired)
        if fits(initial) { return initial }
        var lower: CGFloat = 0.1
        var upper = desired
        for _ in 0..<18 {
            let middle = (lower + upper) / 2
            if fits(layout(middle)) { lower = middle } else { upper = middle }
        }
        return layout(lower)
    }
}

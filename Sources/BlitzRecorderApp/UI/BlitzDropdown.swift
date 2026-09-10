import AppKit
import SwiftUI

enum BlitzDropdownWidth {
    case content
    case fill
}

enum BlitzDropdownMetrics {
    static let fontSize: CGFloat = 12
    static let horizontalPadding: CGFloat = 11
    static let spacing: CGFloat = 8
    static let chevronWidth: CGFloat = 10
    static let maximumContentWidth: CGFloat = 280

    static func contentWidth(_ titles: [String]) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let textWidth = titles.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let chromeWidth = horizontalPadding * 2 + spacing + chevronWidth
        return min(maximumContentWidth, max(72, ceil(textWidth) + chromeWidth + 2))
    }
}

struct BlitzDropdownValueLabel: View {
    let value: String

    var body: some View {
        Text(value)
            .font(.system(size: BlitzDropdownMetrics.fontSize, weight: .medium))
            .foregroundStyle(BlitzUI.primaryText)
            .lineLimit(2)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .help(value)
    }
}

struct BlitzDropdownOption<Value: Hashable> {
    let value: Value
    let title: String
    let detail: String?
    var isEnabled = true
}

struct BlitzDropdown<Value: Hashable>: View {
    struct Configuration {
        let title: String
        let selection: Binding<Value>
        let options: [BlitzDropdownOption<Value>]
        var menuWidth: CGFloat = 280
        var width: BlitzDropdownWidth = .fill
    }

    let configuration: Configuration

    private var selectedTitle: String {
        configuration.options.first { $0.value == configuration.selection.wrappedValue }?.title ?? "Choose…"
    }

    private var contentWidth: CGFloat {
        BlitzDropdownMetrics.contentWidth(configuration.options.map(\.title) + [selectedTitle])
    }

    var body: some View {
        BlitzGlassMenu(entries: entries, menuWidth: configuration.menuWidth) {
            HStack(spacing: BlitzDropdownMetrics.spacing) {
                BlitzDropdownValueLabel(value: selectedTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                BlitzMenuChevron()
                    .frame(width: BlitzDropdownMetrics.chevronWidth)
                    .fixedSize()
            }
            .padding(.horizontal, BlitzDropdownMetrics.horizontalPadding)
            .padding(.vertical, 7)
            .frame(width: configuration.width == .content ? contentWidth : nil)
            .frame(
                minWidth: configuration.width == .fill ? min(120, contentWidth) : nil,
                maxWidth: configuration.width == .fill ? .infinity : nil
            )
            .frame(minHeight: BlitzControlMetrics.height(.regular))
        }
        .layoutPriority(1)
        .disabled(configuration.options.isEmpty)
        .accessibilityLabel(configuration.title)
        .accessibilityValue(selectedTitle)
        .help("\(configuration.title): \(selectedTitle)")
    }

    private var entries: [BlitzMenuEntry] {
        [.section(configuration.title)] + configuration.options.map { option in
            .item(BlitzMenuItem(
                title: option.title,
                subtitle: option.detail,
                systemImage: nil,
                isSelected: configuration.selection.wrappedValue == option.value,
                isEnabled: option.isEnabled,
                action: { configuration.selection.wrappedValue = option.value }
            ))
        }
    }
}

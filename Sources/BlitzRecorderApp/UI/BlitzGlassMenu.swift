import AppKit
import SwiftUI

struct BlitzMenuItem {
    var title: String
    var subtitle: String?
    var systemImage: String?
    var icon: NSImage?
    var selection: Bool?
    var isDestructive: Bool
    var isEnabled: Bool
    var action: () -> Void

    var isSelected: Bool { selection == true }

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String?,
        icon: NSImage? = nil,
        isSelected: Bool? = nil,
        isDestructive: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.icon = icon
        self.selection = isSelected
        self.isDestructive = isDestructive
        self.isEnabled = isEnabled
        self.action = action
    }

    func perform(dismiss: () -> Void) {
        guard isEnabled else { return }
        dismiss()
        action()
    }
}

enum BlitzMenuEntry {
    case item(BlitzMenuItem)
    case divider
    case section(String)
}

struct BlitzGlassMenu<Label: View>: View {
    let entries: [BlitzMenuEntry]
    var menuWidth: CGFloat = 240
    @ViewBuilder var label: () -> Label

    @State private var isPresented = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            label()
                .contentShape(.rect)
        }
        .buttonStyle(BlitzMenuTriggerStyle(isPresented: isPresented))
        .onChange(of: isEnabled) {
            if !isEnabled { isPresented = false }
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            BlitzMenuList(entries: entries, width: menuWidth, maxHeight: adaptivePopoverMaxHeight) {
                isPresented = false
            }
            .preferredColorScheme(.dark)
        }
    }

    private var adaptivePopoverMaxHeight: CGFloat {
        let visibleHeight = NSScreen.main?.visibleFrame.height ?? 720
        return min(520, max(260, visibleHeight - 120))
    }
}

struct BlitzMenuList: View {
    let entries: [BlitzMenuEntry]
    let width: CGFloat
    let maxHeight: CGFloat
    let dismiss: () -> Void
    @State private var highlightedIndex: Int?

    private var itemIndices: [Int] {
        BlitzMenuNavigation.enabledIndices(entries)
    }

    private var contentHeight: CGFloat {
        entries.reduce(BlitzControlMetrics.menuPadding * 2) { height, entry in
            switch entry {
            case .item(let item): height + BlitzMenuRow.height(item)
            case .divider: height + BlitzControlMetrics.dividerHeight
            case .section: height + BlitzControlMetrics.sectionHeight
            }
        }
    }

    private var adaptiveWidth: CGFloat {
        let visibleWidth = NSScreen.main?.visibleFrame.width ?? width
        return min(width, max(220, visibleWidth - 32))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        Group {
                            switch entry {
                            case .item(let item):
                                BlitzMenuRow(
                                    item: item,
                                    isHighlighted: highlightedIndex == index,
                                    onHighlight: { highlightedIndex = index },
                                    dismiss: dismiss
                                )
                            case .divider:
                                Divider()
                                    .overlay(BlitzUI.separator)
                                    .padding(.horizontal, 8)
                                    .frame(height: BlitzControlMetrics.dividerHeight)
                            case .section(let title):
                                Text(title)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(BlitzUI.secondaryText)
                                    .padding(.horizontal, 10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .frame(height: BlitzControlMetrics.sectionHeight)
                            }
                        }
                        .id(index)
                    }
                }
                .padding(BlitzControlMetrics.menuPadding)
            }
            .scrollIndicators(.automatic)
            .onChange(of: highlightedIndex) {
                if let highlightedIndex { proxy.scrollTo(highlightedIndex) }
            }
        }
        .frame(width: adaptiveWidth)
        .frame(height: min(contentHeight, maxHeight))
        .background(BlitzUI.panelBackground)
        .background {
            BlitzMenuKeyboardHandler { command in
                switch command {
                case .previous: moveHighlight(-1)
                case .next: moveHighlight(1)
                case .select: activateHighlighted()
                case .dismiss: dismiss()
                }
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
        .onAppear {
            highlightedIndex = BlitzMenuNavigation.initialIndex(entries)
        }
        .onChange(of: itemIndices) {
            if highlightedIndex.map({ !itemIndices.contains($0) }) ?? true {
                highlightedIndex = BlitzMenuNavigation.initialIndex(entries)
            }
        }
    }

    private func moveHighlight(_ offset: Int) {
        highlightedIndex = BlitzMenuNavigation.movedIndex(.init(
            entries: entries, currentIndex: highlightedIndex, offset: offset
        ))
    }

    private func activateHighlighted() {
        guard let highlightedIndex, entries.indices.contains(highlightedIndex),
              case .item(let item) = entries[highlightedIndex] else { return }
        item.perform(dismiss: dismiss)
    }
}

struct BlitzMenuRow: View {
    let item: BlitzMenuItem
    let isHighlighted: Bool
    let onHighlight: () -> Void
    let dismiss: () -> Void
    @State private var isHovering = false

    static func height(_ item: BlitzMenuItem) -> CGFloat {
        item.subtitle?.isEmpty == false ? BlitzControlMetrics.detailedRowHeight : BlitzControlMetrics.rowHeight
    }

    var body: some View {
        Button(role: item.isDestructive ? .destructive : nil) {
            item.perform(dismiss: dismiss)
        } label: {
            HStack(spacing: 9) {
                if let icon = item.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                        .clipShape(.rect(cornerRadius: 4))
                } else if let systemImage = item.systemImage {
                    BlitzSymbol(configuration: .init(name: systemImage, size: 16))
                        .foregroundStyle(iconColor)
                        .frame(width: 18, height: 18)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(textColor)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)

                    if let subtitle = item.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(BlitzUI.secondaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                if item.selection != nil {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(BlitzUI.mint)
                        .opacity(item.isSelected ? 1 : 0)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Self.height(item))
            .background(item.isEnabled && (isHighlighted || isHovering) ? BlitzUI.selectedFill : .clear, in: .rect(cornerRadius: 7))
            .contentShape(.rect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover {
            isHovering = $0
            if $0 && item.isEnabled { onHighlight() }
        }
        .accessibilityAddTraits(item.isSelected ? [.isSelected] : [])
        .pointingHandCursor()
        .disabled(!item.isEnabled)
        .opacity(item.isEnabled ? 1 : 0.4)
        .help(item.subtitle.map { "\(item.title) — \($0)" } ?? item.title)
    }

    private var textColor: Color {
        item.isDestructive ? BlitzUI.recordRed : BlitzUI.primaryText
    }

    private var iconColor: Color {
        item.isDestructive ? BlitzUI.recordRed : BlitzUI.secondaryText
    }
}

import AppKit
import SwiftUI

struct BlitzSourcePickerItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let systemImage: String
    let icon: NSImage?
    let thumbnail: NSImage?
    let isSelected: Bool
    var visibility: SourcePickerVisibility? = nil
    var screenKind: ScreenSourceBinding.Kind? = nil
    var loadThumbnail: (() async -> NSImage?)? = nil
    let action: () -> Void

    func menuItem(isChoice: Bool) -> BlitzMenuItem {
        BlitzMenuItem(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            icon: icon,
            isSelected: isChoice ? isSelected : nil,
            action: action
        )
    }
}

struct BlitzSourcePickerSection {
    let title: String
    let items: [BlitzSourcePickerItem]
}

struct BlitzSourcePickerModel {
    enum Layout {
        case list
        case thumbnails
    }

    let title: String
    let subtitle: String
    let systemImage: String
    let icon: NSImage?
    let sections: [BlitzSourcePickerSection]
    let actions: [BlitzSourcePickerItem]
    let layout: Layout
    let enabled: Bool
    var hiddenSections: [BlitzSourcePickerSection] = []
    var prompt = "Choose source"
    var refresh: (() async -> Void)? = nil

    struct SectionsRequest {
        let preferences: SourcePickerPreferences
        let includeHidden: Bool
    }

    func organizedSections(_ request: SectionsRequest) -> [BlitzSourcePickerSection] {
        (sections + hiddenSections).compactMap { section in
            let items = section.items.filter { item in
                let isHidden = item.visibility.map(request.preferences.isHidden) ?? false
                return request.includeHidden ? isHidden && !item.isSelected : !isHidden || item.isSelected
            }
            return items.isEmpty ? nil : BlitzSourcePickerSection(title: section.title, items: items)
        }
    }

    func menuEntries(_ visibleSections: [BlitzSourcePickerSection]) -> [BlitzMenuEntry] {
        var entries: [BlitzMenuEntry] = visibleSections.filter { !$0.items.isEmpty }.flatMap { section in
            [.section(section.title)] + section.items.map { .item($0.menuItem(isChoice: true)) }
        }
        if !actions.isEmpty {
            if !entries.isEmpty { entries.append(.divider) }
            entries += actions.map { .item($0.menuItem(isChoice: false)) }
        }
        return entries.isEmpty ? [.section("No sources available")] : entries
    }
}

struct BlitzSourcePicker: View {
    let model: BlitzSourcePickerModel

    @State private var isPresented = false
    @Environment(\.isEnabled) private var isEnabled

    private var canOpen: Bool { model.enabled && isEnabled }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 10) {
                sourceIcon

                VStack(alignment: .leading, spacing: 2) {
                    BlitzDropdownValueLabel(value: model.title)

                    Text(model.subtitle)
                        .font(BlitzType.footnote)
                        .foregroundStyle(model.enabled ? BlitzUI.secondaryText : BlitzUI.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 4)

                BlitzMenuChevron()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minHeight: 54)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(BlitzMenuTriggerStyle(isPresented: isPresented))
        .disabled(!model.enabled)
        .onChange(of: canOpen) {
            if !canOpen { isPresented = false }
        }
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            BlitzSourcePickerPopover(model: model) {
                isPresented = false
            }
            .preferredColorScheme(.dark)
        }
    }

    @ViewBuilder
    private var sourceIcon: some View {
        if let icon = model.icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .padding(5)
                .clipShape(.rect(cornerRadius: BlitzUI.controlRadius))
        } else {
            BlitzSymbol(configuration: .init(name: model.systemImage, size: 22))
                .foregroundStyle(model.enabled ? BlitzUI.mint : BlitzUI.tertiaryText)
                .frame(width: 34, height: 34)
        }
    }
}

struct BlitzSourcePickerThumbnailCard: View {
    let item: BlitzSourcePickerItem
    let previewRevision: Int
    let dismiss: () -> Void

    @State private var isHovering = false
    @State private var thumbnail = SourcePickerThumbnailState()

    private var thumbnailID: SourcePickerThumbnailID {
        .init(sourceID: item.id, revision: previewRevision)
    }

    var body: some View {
        Button {
            dismiss()
            item.action()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                preview

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(BlitzType.captionEmphasis)
                        .foregroundStyle(BlitzUI.primaryText)
                        .lineLimit(2)
                        .frame(height: 30, alignment: .topLeading)
                        .truncationMode(.tail)

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(BlitzType.footnote)
                            .foregroundStyle(BlitzUI.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
            }
            .background(rowFill, in: .rect(cornerRadius: BlitzUI.controlRadius))
            .overlay(alignment: .topTrailing) {
                if item.isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(BlitzType.glyph(14))
                        .foregroundStyle(BlitzUI.mint)
                        .background(Circle().fill(.black))
                        .padding(6)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(.rect(cornerRadius: BlitzUI.controlRadius))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(item.isSelected ? [.isSelected] : [])
        .pointingHandCursor()
        .help([item.title, item.subtitle].compactMap { $0 }.joined(separator: " — "))
        .task(id: thumbnailID) {
            await thumbnail.load(.init(id: thumbnailID, load: item.loadThumbnail))
        }
    }

    private var preview: some View {
        ZStack {
            Color.black.opacity(0.44)

            if let thumbnail = (thumbnail.id == thumbnailID ? thumbnail.image : nil) ?? item.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [BlitzUI.hoverFill, BlitzUI.cardFill],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                VStack(spacing: 8) {
                    BlitzSymbol(configuration: .init(name: item.systemImage, size: 26))
                        .foregroundStyle(BlitzUI.secondaryText)
                    Text(thumbnail.isLoading ? "Loading preview…" : "Preview unavailable")
                        .font(BlitzType.footnote)
                        .foregroundStyle(BlitzUI.secondaryText)
                }
            }

            VStack {
                HStack {
                    if let icon = item.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 22, height: 22)
                            .padding(4)
                            .background(.black.opacity(0.66), in: .rect(cornerRadius: BlitzUI.controlRadius))
                    }

                    Spacer(minLength: 0)

                    Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                        .font(BlitzType.glyph(16))
                        .foregroundStyle(item.isSelected ? BlitzUI.mint : BlitzUI.supportingText)
                        .shadow(color: .black.opacity(0.7), radius: 3)
                }
                Spacer(minLength: 0)
            }
            .padding(7)
        }
        .frame(height: 136)
        .clipShape(.rect(topLeadingRadius: 9, topTrailingRadius: 9))
    }

    private var rowFill: Color {
        if item.isSelected {
            return BlitzUI.selectedFill
        }
        return isHovering ? BlitzUI.hoverFill : BlitzUI.cardFill
    }
}

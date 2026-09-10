import AppKit
import SwiftUI

struct BlitzSourcePickerPopover: View {
    let model: BlitzSourcePickerModel
    let dismiss: () -> Void

    @AppStorage("sourcePicker.visibility.v1") private var encodedPreferences = "{}"
    @State private var showsHiddenSources = false
    @State private var isEditingSources = false
    @State private var previewRevision = 0
    @State private var isRefreshing = false
    @State private var screenKind: ScreenSourceBinding.Kind = .window

    private var preferences: SourcePickerPreferences {
        SourcePickerPreferences(encoded: encodedPreferences)
    }

    private var mainSections: [BlitzSourcePickerSection] {
        filteredSections(model.organizedSections(.init(preferences: preferences, includeHidden: false)))
    }

    private var hiddenSections: [BlitzSourcePickerSection] {
        filteredSections(model.organizedSections(.init(preferences: preferences, includeHidden: true)))
    }

    private var hiddenCount: Int { hiddenSections.reduce(0) { $0 + $1.items.count } }
    private var width: CGFloat { model.layout == .thumbnails && !isEditingSources ? 560 : 360 }
    private var browserHeight: CGFloat { min(400, max(200, (NSScreen.main?.visibleFrame.height ?? 720) - 330)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(BlitzUI.separator)

            if isEditingSources {
                managementList
            } else if model.layout == .list {
                BlitzMenuList(
                    entries: selectionEntries,
                    width: width,
                    maxHeight: browserHeight,
                    dismiss: dismiss
                )
            } else {
                screenKinds
                thumbnailBrowser
            }

            Divider().overlay(BlitzUI.separator)
            footer
        }
        .frame(width: width)
        .background(BlitzUI.panelBackground)
        .onAppear {
            if let selectedKind = (model.sections + model.hiddenSections)
                .flatMap(\.items).first(where: \.isSelected)?.screenKind {
                screenKind = selectedKind
            }
        }
        .onChange(of: screenKind) { showsHiddenSources = false }
        .task { await model.refresh?() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(isEditingSources ? "Edit sources" : model.prompt)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BlitzUI.primaryText)
            Spacer()
            if isEditingSources {
                Button("Done") { isEditingSources = false }
                    .blitzButton(.secondary)
                    .controlSize(.small)
            } else if model.refresh != nil {
                Button {
                    isRefreshing = true
                    Task {
                        await model.refresh?()
                        previewRevision += 1
                        isRefreshing = false
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .blitzButton(.quiet)
                .controlSize(.small)
                .disabled(isRefreshing)
                .accessibilityLabel("Refresh sources")
                .help("Refresh sources and previews")
            }
        }
        .padding(12)
    }

    private var selectionEntries: [BlitzMenuEntry] {
        let visible = showsHiddenSources ? model.sections + model.hiddenSections : mainSections
        return visible.filter { !$0.items.isEmpty }.flatMap { section in
            [.section(section.title)] + section.items.map { .item($0.menuItem(isChoice: true)) }
        }
    }

    private func filteredSections(_ sections: [BlitzSourcePickerSection]) -> [BlitzSourcePickerSection] {
        guard model.layout == .thumbnails else { return sections }
        return sections.compactMap { section in
            let items = section.items.filter { $0.screenKind == screenKind }
            return items.isEmpty ? nil : .init(title: section.title, items: items)
        }
    }

    private var screenKinds: some View {
        BlitzSegmentedPicker(configuration: .init(
            title: "Source type",
            options: [.window, .display, .application],
            selection: $screenKind,
            label: { kind in
                switch kind {
                case .window: "Windows"
                case .display: "Displays"
                case .application: "Apps"
                }
            }
        ))
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    private var thumbnailBrowser: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if mainSections.isEmpty && !showsHiddenSources {
                        Text("No sources here. Check hidden sources or refresh the list.")
                            .font(.system(size: 12))
                            .foregroundStyle(BlitzUI.secondaryText)
                            .frame(maxWidth: .infinity, minHeight: 100)
                    }
                    ForEach(mainSections, id: \.title) { section in
                        sourceSection(section)
                    }
                    if showsHiddenSources {
                        Text("Hidden sources")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(BlitzUI.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("hidden")
                        ForEach(hiddenSections, id: \.title) { section in
                            sourceSection(section)
                        }
                    }
                }
                .padding(12)
            }
            .scrollIndicators(.visible)
            .onChange(of: showsHiddenSources) {
                if showsHiddenSources { proxy.scrollTo("hidden", anchor: .top) }
            }
            .id(screenKind)
        }
        .frame(height: browserHeight)
    }

    private func sourceSection(_ section: BlitzSourcePickerSection) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(section.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(BlitzUI.secondaryText)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(section.items) { item in
                    BlitzSourcePickerThumbnailCard(item: item, previewRevision: previewRevision, dismiss: dismiss)
                        .contextMenu {
                            if let visibility = item.visibility {
                                Button(preferences.isHidden(visibility) ? "Show in picker" : "Hide from picker") {
                                    toggleVisibility(visibility)
                                }
                            }
                        }
                }
            }
        }
    }

    private var managementList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Choose what appears first. Hidden sources stay available below.")
                .font(.system(size: 11))
                .foregroundStyle(BlitzUI.secondaryText)
                .padding(12)
            BlitzMenuList(entries: managementEntries, width: width, maxHeight: browserHeight, dismiss: {})
        }
    }

    private var managementEntries: [BlitzMenuEntry] {
        (model.sections + model.hiddenSections)
            .filter { $0.items.contains { $0.visibility != nil } }
            .flatMap { section in
            [.section(section.title)] + section.items.compactMap { item in
                guard let visibility = item.visibility else { return nil }
                let isHidden = preferences.isHidden(visibility)
                let detail = isHidden
                    ? (item.isSelected ? "Hidden after switching to another source" : "Hidden · click to restore")
                    : "Shown · click to hide"
                return .item(BlitzMenuItem(
                    title: item.title,
                    subtitle: detail,
                    systemImage: isHidden ? "eye.slash" : "eye",
                    action: { toggleVisibility(visibility) }
                ))
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            if !isEditingSources {
                if hiddenCount > 0 {
                    menuCommand(BlitzMenuItem(
                        title: showsHiddenSources ? "Collapse hidden sources" : "Hidden sources (\(hiddenCount))",
                        systemImage: showsHiddenSources ? "chevron.up" : "chevron.down",
                        action: { showsHiddenSources.toggle() }
                    ))
                }
                if (model.sections + model.hiddenSections).contains(where: { $0.items.contains { $0.visibility != nil } }) {
                    menuCommand(BlitzMenuItem(
                        title: "Edit sources…",
                        systemImage: "slider.horizontal.3",
                        action: { isEditingSources = true }
                    ))
                }
                ForEach(model.actions) { item in
                    BlitzMenuRow(
                        item: item.menuItem(isChoice: false),
                        isHighlighted: false, onHighlight: {}, dismiss: dismiss
                    )
                }
            }
        }
        .padding(isEditingSources ? 0 : 8)
    }

    private func menuCommand(_ item: BlitzMenuItem) -> some View {
        BlitzMenuRow(item: item, isHighlighted: false, onHighlight: {}, dismiss: {})
    }

    private func toggleVisibility(_ source: SourcePickerVisibility) {
        var updated = preferences
        updated.update(.init(id: source.id, isHidden: !updated.isHidden(source)))
        encodedPreferences = updated.encoded
    }
}

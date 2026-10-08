#if DEBUG
import AppKit
import SwiftUI

@MainActor
final class BlitzUIKitWindow: NSObject {
    static let shared = BlitzUIKitWindow()
    private var window: NSWindow?

    @objc func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1180, height: 860),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "UI Kit"
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: BlitzUIKitView())
        window.center()
        return window
    }
}

struct BlitzUIKitView: View {
    @StateObject private var updates = BlitzUIKitView.demoUpdates()

    var body: some View {
        ScrollView {
            BlitzUIKitContent()
        }
        .background(BlitzUI.panelBackground)
        .environmentObject(updates)
    }

    static func demoUpdates() -> AppUpdateController {
        let updates = AppUpdateController()
        updates.prepareInstallation(.init(version: "9.9.9", install: {}))
        return updates
    }
}

struct BlitzUIKitContent: View {
    static let sections: [(String, AnyView)] = [
        ("colors", AnyView(BlitzUIKitColors())), ("type", AnyView(BlitzUIKitTypography())),
        ("icons", AnyView(BlitzUIKitIcons())), ("buttons", AnyView(BlitzUIKitButtons())),
        ("inputs", AnyView(BlitzUIKitInputs())), ("menus", AnyView(BlitzUIKitMenus())),
        ("status", AnyView(BlitzUIKitStatus())), ("loading", AnyView(BlitzUIKitLoading())),
        ("animations", AnyView(BlitzUIKitAnimations())), ("inspector", AnyView(BlitzUIKitInspector())),
        ("editor", AnyView(BlitzUIKitEditor())), ("recording", AnyView(BlitzUIKitRecording())),
        ("navigation", AnyView(BlitzUIKitNavigation())), ("library-rows", AnyView(BlitzUIKitLibrary())),
        ("library-parts", AnyView(BlitzUIKitLibraryParts())), ("sharing", AnyView(BlitzUIKitSharing())),
        ("popovers", AnyView(BlitzUIKitPopovers())), ("settings", AnyView(BlitzUIKitSettings())),
        ("unused", AnyView(BlitzUIKitUnused())),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 4) {
                Text("BlitzRecorder UI Kit").font(BlitzType.largeTitle)
                Text("Every shared control, loading state and animation, live. Hover and click work. Dev builds only.")
                    .font(BlitzType.body)
                    .foregroundStyle(BlitzUI.secondaryText)
            }
            ForEach(BlitzUIKitContent.sections, id: \.0) { $0.1 }
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BlitzUI.panelBackground)
        .foregroundStyle(BlitzUI.primaryText)
        .preferredColorScheme(.dark)
    }
}

struct BlitzUIKitSection<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle().fill(BlitzUI.separator).frame(height: 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(BlitzType.title)
                Text(detail).font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BlitzUIKitSpecimen<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
            Text(label)
                .font(BlitzType.footnote)
                .foregroundStyle(BlitzUI.tertiaryText)
                .monospaced()
        }
    }
}

private struct BlitzUIKitColors: View {
    private struct Swatch: Identifiable {
        let name: String
        let color: Color
        var id: String { name }
    }

    private let accents: [Swatch] = [
        .init(name: "mint", color: BlitzUI.mint), .init(name: "recordRed", color: BlitzUI.recordRed),
        .init(name: "warning", color: BlitzUI.warning),
    ]
    private let surfaces: [Swatch] = [
        .init(name: "canvasBackground", color: BlitzUI.canvasBackground),
        .init(name: "projectLibraryBackground", color: BlitzUI.projectLibraryBackground),
        .init(name: "panelBackground", color: BlitzUI.panelBackground),
        .init(name: "cardFill", color: BlitzUI.cardFill), .init(name: "quietFill", color: BlitzUI.quietFill),
        .init(name: "controlFill", color: BlitzUI.controlFill), .init(name: "hoverFill", color: BlitzUI.hoverFill),
        .init(name: "selectedFill", color: BlitzUI.selectedFill), .init(name: "strongFill", color: BlitzUI.strongFill),
    ]
    private let text: [Swatch] = [
        .init(name: "primaryText", color: BlitzUI.primaryText), .init(name: "supportingText", color: BlitzUI.supportingText),
        .init(name: "secondaryText", color: BlitzUI.secondaryText), .init(name: "tertiaryText", color: BlitzUI.tertiaryText),
        .init(name: "separator", color: BlitzUI.separator), .init(name: "panelStroke", color: BlitzUI.panelStroke),
    ]

    var body: some View {
        BlitzUIKitSection(title: "Colors", detail: "Mint = selected or active only. Red = record only. Amber = warnings only.") {
            row(accents)
            row(surfaces)
            row(text)
        }
    }

    private func row(_ swatches: [Swatch]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 12, alignment: .leading)], alignment: .leading, spacing: 12) {
            ForEach(swatches) { swatch in
                BlitzUIKitSpecimen(label: swatch.name) {
                    RoundedRectangle(cornerRadius: BlitzUI.controlRadius)
                        .fill(swatch.color)
                        .frame(width: 116, height: 44)
                        .overlay(RoundedRectangle(cornerRadius: BlitzUI.controlRadius).strokeBorder(BlitzUI.panelStroke))
                }
            }
        }
    }
}

private struct BlitzUIKitTypography: View {
    private let styles: [(String, Font)] = [
        ("largeTitle", BlitzType.largeTitle), ("title", BlitzType.title), ("headline", BlitzType.headline),
        ("section", BlitzType.section), ("callout", BlitzType.callout), ("body", BlitzType.body),
        ("label", BlitzType.label), ("strong", BlitzType.strong), ("caption", BlitzType.caption),
        ("captionEmphasis", BlitzType.captionEmphasis), ("footnote", BlitzType.footnote), ("numeric", BlitzType.numeric),
    ]

    var body: some View {
        BlitzUIKitSection(title: "Type", detail: "BlitzType. System font, semibold for emphasis.") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(styles, id: \.0) { name, font in
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text(name)
                            .font(BlitzType.footnote).monospaced()
                            .foregroundStyle(BlitzUI.tertiaryText)
                            .frame(width: 120, alignment: .leading)
                        Text("Record your screen and camera in one take · 05:17").font(font)
                    }
                }
            }
        }
    }
}

private struct BlitzUIKitButtons: View {
    private let emphases: [(String, BlitzButtonEmphasis)] = [
        ("accent", .accent), ("emphasized", .emphasized), ("secondary", .secondary), ("quiet", .quiet),
    ]
    private let sizes: [(String, ControlSize)] = [("mini", .mini), ("small", .small), ("regular", .regular), ("large", .large)]

    var body: some View {
        BlitzUIKitSection(title: "Buttons", detail: ".blitzButton(_:). One accent button per screen.") {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
                GridRow {
                    Text("")
                    ForEach(sizes, id: \.0) { Text($0.0).font(BlitzType.footnote).foregroundStyle(BlitzUI.tertiaryText) }
                    Text("disabled").font(BlitzType.footnote).foregroundStyle(BlitzUI.tertiaryText)
                }
                ForEach(emphases, id: \.0) { name, emphasis in
                    GridRow {
                        Text(name).font(BlitzType.footnote).monospaced().foregroundStyle(BlitzUI.tertiaryText)
                        ForEach(sizes, id: \.0) { _, size in
                            Button("Export", systemImage: "square.and.arrow.up") {}
                                .blitzButton(emphasis)
                                .controlSize(size)
                        }
                        Button("Export", systemImage: "square.and.arrow.up") {}
                            .blitzButton(emphasis)
                            .disabled(true)
                    }
                }
            }
            HStack(spacing: 18) {
                BlitzUIKitSpecimen(label: "record") { Button("Record", systemImage: "record.circle") {}.blitzButton(.record) }
                BlitzUIKitSpecimen(label: "dock") { Button("Screen", systemImage: "display") {}.blitzButton(.dock) }
                BlitzUIKitSpecimen(label: "prominent") { Button("Send to BlitzReels") {}.blitzButton(.prominent) }
                BlitzUIKitSpecimen(label: "secondary · destructive") {
                    Button("Move to Trash", systemImage: "trash", role: .destructive) {}.blitzButton(.secondary)
                }
                BlitzUIKitSpecimen(label: "BlitzToolbarButton") {
                    HStack {
                        BlitzToolbarButton(configuration: .init(title: "Split", symbolName: "scissors", showsTitle: true, action: {}))
                        BlitzToolbarButton(configuration: .init(title: "Dismiss", symbolName: "xmark", showsTitle: false, action: {}))
                    }
                }
            }
        }
    }
}

private struct BlitzUIKitInputs: View {
    private enum Layout: String, CaseIterable { case vertical = "Vertical", landscape = "Landscape", square = "Square" }

    @State private var isOn = true
    @State private var isOff = false
    @State private var layout = Layout.vertical
    @State private var quality = "1080p"
    @State private var volume = 0.7
    @State private var search = ""

    var body: some View {
        BlitzUIKitSection(title: "Inputs", detail: "Toggles, pickers, dropdowns, fields.") {
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    BlitzUIKitSpecimen(label: ".blitzSwitch") {
                        Toggle("Remove background", isOn: $isOn).toggleStyle(.blitzSwitch).frame(width: 240)
                    }
                    BlitzUIKitSpecimen(label: ".blitzSwitch · disabled") {
                        Toggle("Mac audio", isOn: $isOff).toggleStyle(.blitzSwitch).frame(width: 240).disabled(true)
                    }
                    HStack(spacing: 24) {
                        BlitzUIKitSpecimen(label: ".blitzSwitchOnly") { Toggle("On", isOn: $isOn).toggleStyle(.blitzSwitchOnly) }
                        BlitzUIKitSpecimen(label: ".blitzCompactSwitch") { Toggle("On", isOn: $isOn).toggleStyle(.blitzCompactSwitch) }
                        BlitzUIKitSpecimen(label: ".blitzCheckbox") { Toggle("Burn captions", isOn: $isOn).toggleStyle(.blitzCheckbox) }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    BlitzUIKitSpecimen(label: "BlitzSegmentedPicker") {
                        BlitzSegmentedPicker(configuration: .init(
                            title: "Layout", options: Layout.allCases, selection: $layout, label: \.rawValue
                        ))
                        .frame(width: 300)
                    }
                    BlitzUIKitSpecimen(label: "BlitzDropdown") {
                        BlitzDropdown(configuration: .init(
                            title: "Quality", selection: $quality,
                            options: ["720p", "1080p", "4K"].map { .init(value: $0, title: $0, detail: nil) }
                        ))
                        .frame(width: 220)
                    }
                    BlitzUIKitSpecimen(label: "BlitzPlaybackVolumeControl") {
                        BlitzPlaybackVolumeControl(configuration: .init(
                            volume: $volume, sliderWidth: 64...96, onToggleMute: { volume = volume == 0 ? 0.7 : 0 }
                        ))
                    }
                    BlitzUIKitSpecimen(label: "TextField · roundedBorder") {
                        TextField("Folder name", text: $search).textFieldStyle(.roundedBorder).frame(width: 240)
                    }
                }
            }
        }
    }
}

private struct BlitzUIKitInspector: View {
    @State private var zoom = 0.35
    @State private var isExpanded = true

    var body: some View {
        BlitzUIKitSection(title: "Inspector", detail: "Right-pane building blocks. Sliders and buttons only.") {
            VStack(alignment: .leading, spacing: 16) {
                BlitzInspectorHeading(configuration: .init(title: "Framing", detail: "Camera layer"))
                BlitzInspectorSlider(configuration: .init(
                    title: "Zoom", value: $zoom, range: 0...1, step: 0.01,
                    valueLabel: "\(Int((zoom * 100).rounded()))%", onEditingChanged: { _ in }, onReset: { zoom = 0 }
                ))
                BlitzInspectorDisclosure(configuration: .init(title: "Silence", detail: "12 pauses", isExpanded: $isExpanded) {
                    Text("Pauses longer than 0.8 s are trimmed on export.")
                        .font(BlitzType.body)
                        .foregroundStyle(BlitzUI.secondaryText)
                })
                EditorInspectorSection(configuration: .init(title: "EditorInspectorSection") {
                    Button("Restore pauses") {}.blitzButton(.secondary)
                })
            }
            .padding(20)
            .frame(width: 320)
            .background(BlitzUI.canvasBackground, in: .rect(cornerRadius: BlitzUI.cardRadius))
        }
    }
}

private struct BlitzUIKitNavigation: View {
    @State private var isSidebarHidden = false

    var body: some View {
        BlitzUIKitSection(title: "Navigation", detail: "App sidebar rows, update card, studio exit.") {
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 2) {
                    BlitzUI.sectionLabel("Library").padding(.horizontal, 8).padding(.bottom, 4)
                    row(.init(item: item("Recordings", "film.stack", detail: nil, trailing: "24"), depth: 0, isSelected: true,
                              isDropTarget: false, tint: nil, pulses: false, disclosure: nil, action: {}))
                    row(.init(item: item("Shared", "link", detail: nil, trailing: nil), depth: 0, isSelected: false,
                              isDropTarget: false, tint: nil, pulses: false, disclosure: nil, action: {}))
                    row(.init(item: item("Editor", "scissors", detail: "trailer", trailing: nil), depth: 0, isSelected: false,
                              isDropTarget: false, tint: nil, pulses: false, disclosure: nil, action: {}))
                    BlitzUI.sectionLabel("Folders").padding(.horizontal, 8).padding(.vertical, 4).padding(.top, 10)
                    row(.init(item: item("Formation IA", "folder", detail: nil, trailing: "12"), depth: 0, isSelected: false,
                              isDropTarget: false, tint: nil, pulses: false,
                              disclosure: .init(isExpanded: true, toggle: {}), action: {}))
                    row(.init(item: item("Module 01", "rectangle.stack", detail: nil, trailing: "4"), depth: 1, isSelected: false,
                              isDropTarget: true, tint: nil, pulses: false, disclosure: nil, action: {}))
                    row(.init(item: item("Module 02", "rectangle.stack", detail: nil, trailing: "8"), depth: 1, isSelected: false,
                              isDropTarget: false, tint: BlitzUI.warning, pulses: false, disclosure: nil, action: {}))
                    row(.init(item: item("Client X", "folder", detail: nil, trailing: "3"), depth: 0, isSelected: false,
                              isDropTarget: false, tint: nil, pulses: false,
                              disclosure: .init(isExpanded: false, toggle: {}), action: {}))
                    Spacer().frame(height: 12)
                    row(.init(item: item("Recording", "record.circle.fill", detail: "02:41", trailing: nil), depth: 0,
                              isSelected: false, isDropTarget: false, tint: BlitzUI.recordRed, pulses: true,
                              disclosure: nil, action: {}))
                    row(.init(item: item("Settings", "gearshape", detail: nil, trailing: "⌘,"), depth: 0, isSelected: false,
                              isDropTarget: false, tint: nil, pulses: false, disclosure: nil, action: {}))
                }
                .padding(10)
                .frame(width: MainWindowChrome.sidebarWidth)
                .background(BlitzUI.panelBackground, in: .rect(cornerRadius: BlitzUI.cardRadius))
                .overlay(RoundedRectangle(cornerRadius: BlitzUI.cardRadius).strokeBorder(BlitzUI.separator))

                VStack(alignment: .leading, spacing: 18) {
                    BlitzUIKitSpecimen(label: "AppUpdateSidebarCard · ready") {
                        AppUpdateSidebarCard().frame(width: MainWindowChrome.sidebarWidth - 20)
                    }
                    HStack(spacing: 24) {
                        BlitzUIKitSpecimen(label: "AppSidebarToggle") { AppSidebarToggle(isSidebarHidden: $isSidebarHidden) }
                        BlitzUIKitSpecimen(label: "StudioExitButton") {
                            StudioExitButton(configuration: .init(destination: .recordings, action: {}))
                        }
                        BlitzUIKitSpecimen(label: "AppUpdateBadge") { AppUpdateBadge() }
                    }
                    Text("Row states: selected · drop target (Module 01) · warning tint (Module 02) · live pulse (Recording)")
                        .font(BlitzType.caption)
                        .foregroundStyle(BlitzUI.secondaryText)
                        .frame(width: 320, alignment: .leading)
                }
            }
        }
    }

    private func item(_ title: String, _ symbol: String, detail: String?, trailing: String?) -> AppSidebarRow.Item {
        .init(destination: .recordings, title: title, symbol: symbol, detail: detail, trailing: trailing, enabled: true)
    }

    private func row(_ configuration: AppSidebarRow.Configuration) -> some View {
        AppSidebarRow(configuration: configuration)
    }
}

private struct BlitzUIKitLibrary: View {
    var body: some View {
        BlitzUIKitSection(title: "Library rows", detail: "Project list rows: lesson, duplicate lesson, shared, transcript match.") {
            VStack(alignment: .leading, spacing: 4) {
                BlitzUI.sectionLabel("Module 01").padding(.horizontal, 6)
                row(.init(title: "trailer", metadata: .empty, lessonNumber: "01", isDuplicateLesson: false,
                          detail: "27 Sep 2026 · 1080p", match: nil, isShared: true, isSelected: true))
                row(.init(title: "Prompting basics", metadata: .empty, lessonNumber: "02", isDuplicateLesson: true,
                          detail: "28 Sep 2026 · 4K", match: nil, isShared: false, isSelected: false))
                row(.init(title: "Maîtriser l'IA pour ton business", metadata: .empty, lessonNumber: nil, isDuplicateLesson: false,
                          detail: "Formation IA · M01L03 · 13:00", match: "00:42 · on travaille ensuite le prompting",
                          isShared: false, isSelected: false))
            }
            .padding(8)
            .frame(width: 340)
            .background(BlitzUI.projectLibraryBackground, in: .rect(cornerRadius: BlitzUI.cardRadius))
        }
    }

    private func row(_ configuration: ProjectLibrarySidebarRow.Configuration) -> some View {
        ProjectLibrarySidebarRow(configuration: configuration)
    }
}

private struct BlitzUIKitIcons: View {
    private let symbols: [(String, String)] = [
        ("screen", BlitzSymbols.screen), ("camera", BlitzSymbols.camera), ("microphone", BlitzSymbols.microphone),
        ("systemAudio", BlitzSymbols.systemAudio), ("scenes", BlitzSymbols.scenes), ("layout", BlitzSymbols.layout),
        ("split", BlitzSymbols.split), ("pictureInPicture", BlitzSymbols.pictureInPicture),
        ("videoQuality", BlitzSymbols.videoQuality),
    ]

    var body: some View {
        BlitzUIKitSection(title: "Icons", detail: "SF Symbols, semibold. Fill variant only when selected.") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 12, alignment: .leading)], alignment: .leading, spacing: 14) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { index, symbol in
                    BlitzUIKitSpecimen(label: symbol.0) {
                        BlitzIconTile(symbolName: symbol.1, isSelected: index == 0, size: 32)
                    }
                }
            }
        }
    }
}
#endif

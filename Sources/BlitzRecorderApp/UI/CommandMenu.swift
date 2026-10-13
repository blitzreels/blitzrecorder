import AppKit
import SwiftUI

/// ⌘K: type a setting, an action or a recording's name and jump straight to it.
struct BlitzCommand: Identifiable {
    enum Group: String, CaseIterable {
        case actions = "Actions"
        case studio = "Studio"
        case appearance = "Appearance"
        case navigation = "Go to"
        case recordings = "Recordings"
    }

    let id: String
    let group: Group
    let title: String
    let detail: String?
    let symbol: String
    let keywords: [String]
    let shortcut: String?
    let run: () -> Void
}

enum BlitzCommandSearch {
    struct Request {
        let commands: [BlitzCommand]
        let query: String
    }

    /// Prefix matches beat word matches beat substring matches; recordings only appear once you type.
    static func results(_ request: Request) -> [BlitzCommand] {
        let query = request.query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else {
            return request.commands.filter { $0.group != .recordings }
        }
        let scored: [(BlitzCommand, Int)] = request.commands.compactMap { command in
            let title = command.title.lowercased()
            let words = title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            let score: Int
            if title.hasPrefix(query) {
                score = 4
            } else if words.contains(where: { $0.hasPrefix(query) }) {
                score = 3
            } else if command.keywords.contains(where: { $0.hasPrefix(query) }) {
                score = 2
            } else if title.contains(query) || command.keywords.contains(where: { $0.contains(query) }) {
                score = 1
            } else {
                return nil
            }
            return (command, score - (command.group == .recordings ? 1 : 0))
        }
        return scored.enumerated()
            .sorted { $0.element.1 != $1.element.1 ? $0.element.1 > $1.element.1 : $0.offset < $1.offset }
            .map(\.element.0)
            .prefix(40)
            .map { $0 }
    }
}

@MainActor
enum BlitzCommandCatalog {
    static func commands(_ vm: RecorderViewModel) -> [BlitzCommand] {
        var commands: [BlitzCommand] = []
        func add(_ command: BlitzCommand) { commands.append(command) }
        let theme = BlitzThemeStore.shared

        add(.init(id: "new-recording", group: .actions, title: "New Recording", detail: "Open the studio",
                  symbol: "record.circle", keywords: ["record", "start", "studio"], shortcut: "⌘N",
                  run: vm.startNewRecording))
        add(.init(id: "import", group: .actions, title: "Import Video…", detail: "MP4, MOV or M4V",
                  symbol: "square.and.arrow.down", keywords: ["file", "open", "add"], shortcut: "⌘I",
                  run: vm.chooseVideoToImport))
        add(.init(id: "live-preview", group: .actions,
                  title: vm.isLivePreviewEnabled ? "Turn Off Live Preview" : "Turn On Live Preview",
                  detail: "Camera, microphone and screen previews while idle", symbol: "eye",
                  keywords: ["preview", "pause", "camera", "privacy"], shortcut: "⌥⌘L",
                  run: { vm.setLivePreviewEnabled(!vm.isLivePreviewEnabled) }))

        let studioPanes: [(String, String, String, [String], () -> Void)] = [
            ("Layout", "Where the screen and camera sit; corners and shadow", "rectangle.split.2x1",
             ["layout", "corners", "shadow", "rounded", "split", "position"], vm.selectLayoutInspector),
            ("Screen", "Screen framing and app window", "display",
             ["screen", "window", "display", "fit", "crop"], { vm.selectSource(.screen) }),
            ("Camera", "Framing, zoom, crop and effects", "video",
             ["camera", "zoom", "crop", "framing", "remove background", "cutout"], { vm.selectSource(.camera) }),
            ("Canvas", "Background and padding", "photo",
             ["canvas", "background", "gradient", "padding", "color"], vm.selectBackgroundLayer)
        ]
        for pane in studioPanes {
            add(.init(id: "studio-\(pane.0)", group: .studio, title: "\(pane.0) Settings", detail: pane.1,
                      symbol: pane.2, keywords: pane.3, shortcut: nil,
                      run: { vm.showRecorder(); pane.4() }))
        }
        let removes = vm.settings.removesCameraBackgroundAfterRecording
        add(.init(id: "remove-background", group: .studio,
                  title: removes ? "Keep Camera Background" : "Remove Camera Background",
                  detail: "Cut yourself out of the camera after recording", symbol: "person.crop.rectangle",
                  keywords: ["cutout", "green screen", "background", "camera"], shortcut: nil,
                  run: { vm.setCameraBackgroundRemovalAfterRecording(!removes) }))
        add(.init(id: "rule-of-thirds", group: .studio,
                  title: vm.settings.showsRuleOfThirdsOverlay ? "Hide Rule of Thirds" : "Show Rule of Thirds",
                  detail: "Preview guide, never recorded", symbol: "squareshape.split.3x3",
                  keywords: ["guides", "grid", "thirds", "framing"], shortcut: nil,
                  run: { vm.setRuleOfThirds(!vm.settings.showsRuleOfThirdsOverlay) }))
        for (index, scene) in vm.currentScenes.enumerated() {
            add(.init(id: "scene-\(scene.id)", group: .studio, title: "Scene: \(vm.sceneLabel(scene))",
                      detail: nil, symbol: "rectangle.on.rectangle", keywords: ["scene", "layout"],
                      shortcut: index < 9 ? "⌘\(index + 1)" : nil,
                      run: { vm.showRecorder(); vm.selectScene(scene.id) }))
        }

        for mode in BlitzAppearanceMode.allCases where mode != theme.mode {
            add(.init(id: "mode-\(mode.rawValue)", group: .appearance, title: "Use \(mode.title) Mode", detail: nil,
                      symbol: mode.symbolName, keywords: ["theme", "appearance", "dark", "light"], shortcut: nil,
                      run: { theme.mode = mode; theme.applyAppearance() }))
        }
        for accent in BlitzAccentTheme.allCases where accent != theme.accent {
            add(.init(id: "accent-\(accent.rawValue)", group: .appearance, title: "Accent: \(accent.title)",
                      detail: nil, symbol: "paintpalette", keywords: ["color", "theme", "accent"], shortcut: nil,
                      run: { theme.accent = accent }))
        }

        add(.init(id: "go-recordings", group: .navigation, title: "Recordings", detail: nil, symbol: "film.stack",
                  keywords: ["library", "projects", "videos"], shortcut: nil,
                  run: { vm.showSidebarDestination(.recordings) }))
        add(.init(id: "go-shared", group: .navigation, title: "Shared Videos", detail: nil, symbol: "link",
                  keywords: ["links", "share", "hosting", "watch"], shortcut: nil,
                  run: { vm.showSidebarDestination(.shared) }))
        if vm.canOpenEditor {
            add(.init(id: "go-editor", group: .navigation, title: "Editor", detail: nil, symbol: "scissors",
                      keywords: ["edit", "timeline", "cut"], shortcut: nil, run: vm.openEditor))
        }
        for pane in SettingsPane.allCases {
            add(.init(id: "settings-\(pane.id)", group: .navigation, title: "Settings: \(pane.title)",
                      detail: pane.subtitle, symbol: pane.systemImage,
                      keywords: ["settings", "preferences"] + pane.subtitle.lowercased().split(separator: " ").map(String.init),
                      shortcut: pane == .recording ? "⌘," : nil,
                      run: { vm.showSettings(pane) }))
        }

        for project in vm.recentProjects {
            add(.init(id: "project-\(project.id)", group: .recordings, title: project.displayTitle,
                      detail: project.recordedAt.formatted(date: .abbreviated, time: .shortened), symbol: "film",
                      keywords: [], shortcut: nil,
                      run: {
                          vm.showSidebarDestination(.recordings)
                          vm.projectLibraryNavigation.selectedProjectIDs = [project.id]
                      }))
        }
        return commands
    }
}

@MainActor
final class BlitzCommandMenuPanel {
    static let shared = BlitzCommandMenuPanel()

    private final class KeyPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private var panel: NSPanel?
    private var monitor: Any?
    private var observer: NSObjectProtocol?

    func toggle(_ vm: RecorderViewModel) {
        if panel != nil { return dismiss() }
        let host = NSHostingView(rootView: BlitzCommandMenuView(
            commands: BlitzCommandCatalog.commands(vm),
            dismiss: { [weak self] in self?.dismiss() }
        ))
        let size = NSSize(width: 580, height: 420)
        let panel = KeyPanel(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.appearance = NSApp.effectiveAppearance
        panel.contentView = host
        let anchor = (NSApp.keyWindow ?? NSApp.mainWindow)?.frame ?? NSScreen.main?.visibleFrame ?? .zero
        panel.setFrameOrigin(NSPoint(x: anchor.midX - size.width / 2, y: anchor.maxY - size.height - 96))
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if event.window !== self?.panel { self?.dismiss() }
            return event
        }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }

    func dismiss() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let observer { NotificationCenter.default.removeObserver(observer) }
        monitor = nil
        observer = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct BlitzCommandMenuView: View {
    let commands: [BlitzCommand]
    let dismiss: () -> Void
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var isFocused: Bool

    private var results: [BlitzCommand] {
        BlitzCommandSearch.results(.init(commands: commands, query: query))
    }

    var body: some View {
        let results = results
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(BlitzType.symbol(15))
                    .foregroundStyle(BlitzUI.secondaryText)
                TextField("Search settings, actions and recordings", text: $query)
                    .textFieldStyle(.plain)
                    .font(BlitzType.headline)
                    .focused($isFocused)
                    .onSubmit { run(results) }
                    .onKeyPress(.downArrow) { move(1, in: results); return .handled }
                    .onKeyPress(.upArrow) { move(-1, in: results); return .handled }
                    .onKeyPress(.escape) { dismiss(); return .handled }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            Rectangle().fill(BlitzUI.separator).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        if results.isEmpty {
                            Text("No matches for “\(query)”")
                                .font(BlitzType.body)
                                .foregroundStyle(BlitzUI.secondaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                        }
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, command in
                            if index == 0 || results[index - 1].group != command.group {
                                Text(command.group.rawValue)
                                    .font(BlitzType.captionEmphasis)
                                    .foregroundStyle(BlitzUI.tertiaryText)
                                    .padding(.horizontal, 10)
                                    .padding(.top, index == 0 ? 4 : 10)
                                    .padding(.bottom, 2)
                            }
                            row(command, isHighlighted: index == highlighted)
                                .id(index)
                                .onHover { if $0 { highlighted = index } }
                                .onTapGesture { highlighted = index; run(results) }
                        }
                    }
                    .padding(8)
                }
                .scrollIndicators(.never)
                .onChange(of: highlighted) { proxy.scrollTo(highlighted) }
            }
        }
        .frame(width: 580, height: 420)
        .background {
            RoundedRectangle(cornerRadius: BlitzUI.surfaceRadius, style: .continuous).fill(.regularMaterial)
        }
        .clipShape(.rect(cornerRadius: BlitzUI.surfaceRadius, style: .continuous))
        .overlay { BlitzEdgeHighlight(cornerRadius: BlitzUI.surfaceRadius) }
        .onChange(of: query) { highlighted = 0 }
        .onAppear { isFocused = true }
    }

    private func row(_ command: BlitzCommand, isHighlighted: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: command.symbol)
                .font(BlitzType.symbol(14))
                .foregroundStyle(isHighlighted ? BlitzUI.accent : BlitzUI.secondaryText)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(command.title)
                    .font(BlitzType.navigation)
                    .foregroundStyle(BlitzUI.primaryText)
                    .lineLimit(1)
                if let detail = command.detail {
                    Text(detail)
                        .font(BlitzType.caption)
                        .foregroundStyle(BlitzUI.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let shortcut = command.shortcut {
                Text(shortcut)
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.tertiaryText)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background {
            if isHighlighted { BlitzSelectedBackground(cornerRadius: BlitzUI.controlRadius) }
        }
        .contentShape(.rect)
    }

    private func move(_ step: Int, in results: [BlitzCommand]) {
        guard !results.isEmpty else { return }
        highlighted = (highlighted + step + results.count) % results.count
    }

    private func run(_ results: [BlitzCommand]) {
        guard results.indices.contains(highlighted) else { return }
        let command = results[highlighted]
        dismiss()
        command.run()
    }
}

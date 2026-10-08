#if DEBUG
import SwiftUI

struct BlitzUIKitGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BlitzUI.sectionLabel(title)
            BlitzUIKitFlow(spacing: 22) { content() }
        }
    }
}

struct BlitzUIKitFlow: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0,
                      height: rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: .init(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            let gap = rows[rows.count - 1].indices.isEmpty ? 0 : spacing
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += gap + size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}

struct BlitzUIKitStatus: View {
    var body: some View {
        BlitzUIKitSection(title: "Status", detail: "Dots and badges.") {
            BlitzUIKitGroup("BlitzStatusDot · SettingsStatusBadge") {
                ForEach(Array(tones.enumerated()), id: \.offset) { _, tone in
                    BlitzUIKitSpecimen(label: tone.0) {
                        HStack(spacing: 10) {
                            BlitzStatusDot(tone: tone.1)
                            SettingsStatusBadge(configuration: .init(title: tone.0.capitalized, tone: tone.1))
                        }
                    }
                }
                BlitzUIKitSpecimen(label: "BlitzTimecode") {
                    BlitzTimecode(configuration: .init(time: 81.4, duration: 317)).font(BlitzType.numeric)
                }
            }
        }
    }

    private let tones: [(String, BlitzStatusTone)] = [("recording", .recording), ("live", .live), ("ready", .ready), ("warning", .warning), ("muted", .muted)]
}

struct BlitzUIKitMenus: View {
    private enum Tab: String, CaseIterable { case layout = "Layout", screen = "Screen", camera = "Camera" }

    @State private var tab = Tab.camera
    @State private var quality = "1080p"
    @State private var background = CanvasBackgroundStyle.graphite
    @State private var framing = CameraContentMode.fill
    @State private var inspectorTab = EditorInspectorTab.layout
    @State private var choice = 0

    var body: some View {
        BlitzUIKitSection(title: "Menus, tabs & pickers", detail: "Glass menus, tabs, visual choices, scene presets.") {
            BlitzUIKitGroup("Menus") {
                BlitzUIKitSpecimen(label: "BlitzGlassMenu · click") {
                    BlitzGlassMenu(entries: menuEntries) {
                        HStack(spacing: 6) {
                            BlitzDropdownValueLabel(value: "Formation IA")
                            BlitzMenuChevron()
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                    }
                }
                BlitzUIKitSpecimen(label: "BlitzOverflowMenu · inline small / regular") {
                    HStack {
                        BlitzOverflowMenu(configuration: overflow(.inline)).controlSize(.small)
                        BlitzOverflowMenu(configuration: overflow(.inline)).controlSize(.regular)
                    }
                }
                BlitzUIKitSpecimen(label: "BlitzOverflowMenu · dock / busy") {
                    HStack {
                        BlitzOverflowMenu(configuration: overflow(.dock))
                        BlitzOverflowMenu(configuration: .init(entries: menuEntries, menuWidth: 220, placement: .inline,
                                                               isBusy: true, accessibilityLabel: "More", help: "More"))
                            .controlSize(.small)
                    }
                }
                BlitzUIKitSpecimen(label: "BlitzFormDropdown") {
                    BlitzFormDropdown(configuration: .init(
                        title: "Quality", selection: $quality,
                        options: ["720p", "1080p", "4K"].map { .init(value: $0, title: $0, detail: nil) }
                    ))
                    .frame(width: 200)
                }
                BlitzUIKitSpecimen(label: "BlitzMenuTriggerStyle · closed / open") {
                    HStack {
                        Button {} label: { Text("Save to Projects").padding(.horizontal, 10).frame(height: 30) }
                            .buttonStyle(BlitzMenuTriggerStyle(isPresented: false))
                        Button {} label: { Text("Save to Projects").padding(.horizontal, 10).frame(height: 30) }
                            .buttonStyle(BlitzMenuTriggerStyle(isPresented: true))
                    }
                }
            }
            BlitzUIKitGroup("Tabs") {
                BlitzUIKitSpecimen(label: "BlitzTab · symbol above") {
                    HStack(spacing: 2) {
                        ForEach(Tab.allCases, id: \.self) { value in
                            BlitzTab(configuration: .init(
                                title: value.rawValue, symbolName: "video", symbolPlacement: .above,
                                isSelected: tab == value, expands: false, action: { tab = value }
                            ))
                        }
                    }
                    .blitzTabGroup()
                }
                BlitzUIKitSpecimen(label: "BlitzToolTabBar · EditorInspectorTabBar (wide / wraps)") {
                    VStack {
                        EditorInspectorTabBar(selection: $inspectorTab).frame(width: 520)
                        EditorInspectorTabBar(selection: $inspectorTab).frame(width: 300)
                    }
                }
                BlitzUIKitSpecimen(label: "SourceFramingPicker") {
                    SourceFramingPicker(selection: $framing).frame(width: 200)
                }
                BlitzUIKitSpecimen(label: "Frame ratio grid · BlitzTab in a tab group") {
                    LazyVGrid(columns: EditorFrameRatio.columns, spacing: 2) {
                        ForEach(EditorFrameRatioPreset.allCases) { preset in
                            BlitzTab(configuration: .init(title: preset.title, symbolName: nil,
                                                          isSelected: preset == .portrait, expands: true, action: {}))
                        }
                    }
                    .blitzTabGroup()
                    .frame(width: 240)
                }
                BlitzUIKitSpecimen(label: "BlitzSelectionButtonStyle · selected / not") {
                    HStack {
                        Button("Selected") {}.buttonStyle(BlitzSelectionButtonStyle(isSelected: true))
                        Button("Normal") {}.buttonStyle(BlitzSelectionButtonStyle(isSelected: false))
                    }
                }
            }
            BlitzUIKitGroup("Visual choices") {
                BlitzUIKitSpecimen(label: "BlitzVisualChoice") {
                    HStack(spacing: 8) {
                        ForEach(0..<3) { index in
                            BlitzVisualChoice(configuration: .init(
                                title: ["Outline", "Background", "None"][index], help: "", isSelected: choice == index,
                                action: { choice = index },
                                preview: { RoundedRectangle(cornerRadius: 4).fill(BlitzUI.strongFill).frame(height: 30) }
                            ))
                            .frame(width: 96)
                        }
                    }
                }
                BlitzUIKitSpecimen(label: "CaptionStylePreview") {
                    HStack { ForEach(CaptionStyle.allCases, id: \.self) { CaptionStylePreview(style: $0).frame(width: 120, height: 60) } }
                }
                BlitzUIKitSpecimen(label: "BlitzBackgroundPicker (popover)") {
                    BlitzBackgroundPicker(configuration: .init(selection: background, onSelect: { background = $0 }))
                        .frame(width: 260)
                }
                BlitzUIKitSpecimen(label: "BlitzBackgroundPalette") {
                    BlitzBackgroundPalette(configuration: .init(selection: background, onSelect: { background = $0 }))
                        .frame(width: 300)
                }
            }
            BlitzUIKitGroup("Scene presets · BlitzScenePresetCard (vertical)") {
                ForEach(Array(ScenePreset.allCases.enumerated()), id: \.offset) { index, preset in
                    BlitzScenePresetCard(preset: preset, layout: .vertical, isSelected: index == 0, isEnabled: index != 3,
                                         availableSources: [.screen, .camera], action: {})
                        .frame(width: 92)
                }
            }
        }
    }

    private func overflow(_ placement: BlitzOverflowMenu.Placement) -> BlitzOverflowMenu.Configuration {
        .init(entries: menuEntries, menuWidth: 220, placement: placement, isBusy: false,
              accessibilityLabel: "More actions", help: "More actions")
    }

    private var menuEntries: [BlitzMenuEntry] {
        [
            .section("Save next take to"),
            .item(.init(title: "Projects", systemImage: "tray", isSelected: false, action: {})),
            .item(.init(title: "Formation IA", subtitle: "Module 01 · next is Lesson 02", systemImage: "folder",
                        isSelected: true, action: {})),
            .item(.init(title: "Disabled item", systemImage: "nosign", isEnabled: false, action: {})),
            .divider,
            .item(.init(title: "Delete folder", systemImage: "trash", isDestructive: true, action: {})),
        ]
    }
}

struct BlitzUIKitEditor: View {
    @State private var time = 81.0
    @State private var rate = EditorPlaybackRate.normal
    @State private var contentMode = CameraContentMode.fill
    @State private var cropZoom = 0.2
    @State private var alignment = CameraInsetAlignment.bottomRight
    @State private var shape = CameraInsetShape.circle
    @State private var size = 0.3
    @State private var split = 0.6
    @State private var illustrated = 0

    var body: some View {
        BlitzUIKitSection(title: "Editor", detail: "Playback, timeline headers, camera controls, silence actions.") {
            BlitzUIKitGroup("Playback") {
                BlitzUIKitSpecimen(label: "EditorPlaybackControls") {
                    EditorPlaybackControls(configuration: .init(
                        time: time, liveTime: nil, duration: 317, isPlaying: false, isEnabled: true, rate: rate,
                        onSeek: { time = $0 }, onTogglePlayback: {}, onRateChange: { rate = $0 }
                    ))
                    .frame(width: 520)
                }
                BlitzUIKitSpecimen(label: "ProjectPlaybackWaveform · drag") {
                    ProjectPlaybackWaveform(samples: (0..<160).map { Float(0.2 + 0.7 * abs(sin(Double($0) / 7))) },
                                            currentTime: time, duration: 317, onScrub: { time = $0 }, onScrubEnd: {})
                        .frame(width: 420, height: 44)
                }
            }
            BlitzUIKitGroup("Timeline") {
                BlitzUIKitSpecimen(label: "EditorTimelineTrackHeader · selected / normal") {
                    VStack(spacing: 2) {
                        EditorTimelineTrackHeader(configuration: .init(
                            title: "Screen", symbol: "display", tint: BlitzUI.trackScreen, status: nil, height: 44,
                            isSelected: true, isInteractive: true, onSelect: {}, accessory: { EmptyView() }))
                        EditorTimelineTrackHeader(configuration: .init(
                            title: "Transcript", symbol: "text.quote", tint: BlitzUI.mint, status: "Loading waveform",
                            height: 44, isSelected: false, isInteractive: true, onSelect: {},
                            accessory: { ProgressView().controlSize(.mini) }))
                    }
                    .frame(width: 200)
                }
                BlitzUIKitSpecimen(label: "EditorTimelineTrackToggle · on / off") {
                    HStack {
                        EditorTimelineTrackToggle(configuration: .init(title: "Camera", isVideo: true, isOff: false,
                                                                       isInteractive: true, onToggle: {}))
                        EditorTimelineTrackToggle(configuration: .init(title: "Mic", isVideo: false, isOff: true,
                                                                       isInteractive: true, onToggle: {}))
                    }
                }
                BlitzUIKitSpecimen(label: "EditorTimelineGrip · idle / active") {
                    HStack(spacing: 16) {
                        EditorTimelineGrip(tint: BlitzUI.trackScreen, isActive: false).frame(width: 10, height: 40)
                        EditorTimelineGrip(tint: BlitzUI.trackScreen, isActive: true).frame(width: 10, height: 40)
                    }
                }
                BlitzUIKitSpecimen(label: "BlitzPaneDivider · drag") {
                    BlitzPaneDivider(configuration: .init(axis: .horizontal, label: "Timeline height", value: $split,
                                                          bounds: 0.2...0.8, defaultValue: 0.6, onCommit: {}))
                        .frame(width: 240, height: 14)
                }
            }
            BlitzUIKitGroup("Camera") {
                BlitzUIKitSpecimen(label: "CameraImageControls") {
                    CameraImageControls(configuration: .init(
                        contentMode: $contentMode, cropZoom: $cropZoom, isCropModeEnabled: false, showsContentMode: true,
                        isResetDisabled: false, onCropZoomEditingChanged: { _ in }, onBeginCrop: {}, onResetCrop: {}
                    ))
                    .frame(width: 260)
                }
                BlitzUIKitSpecimen(label: "CameraImageControls · crop mode") {
                    CameraImageControls(configuration: .init(
                        contentMode: $contentMode, cropZoom: $cropZoom, isCropModeEnabled: true, showsContentMode: true,
                        isResetDisabled: true, onCropZoomEditingChanged: { _ in }, onBeginCrop: {}, onResetCrop: {}
                    ))
                    .frame(width: 260)
                }
                BlitzUIKitSpecimen(label: "CameraInsetFrameControlPanel") {
                    CameraInsetFrameControlPanel(configuration: .init(alignment: $alignment, shape: $shape, size: $size,
                                                                      sizeRange: 0.15...0.5))
                        .frame(width: 260)
                }
                BlitzUIKitSpecimen(label: "CropFloatingToolbar") {
                    CropFloatingToolbar(configuration: .init(onDone: {}, onReset: {}, onCancel: {}))
                }
            }
            BlitzUIKitGroup("Silence actions") {
                BlitzUIKitSpecimen(label: "SilenceTakeStrip") {
                    SilenceTakeStrip(presentation: BlitzUIKitSilence.presentation(.proposed)).frame(width: 300, height: 48)
                }
                BlitzUIKitSpecimen(label: "SilenceStrengthSection") {
                    SilenceStrengthSection(presentation: BlitzUIKitSilence.presentation(.proposed), actions: silenceActions)
                        .frame(width: 300)
                }
                BlitzUIKitSpecimen(label: "SilenceFooterActions · proposed / applied") {
                    VStack(spacing: 12) {
                        SilenceFooterActions(presentation: BlitzUIKitSilence.presentation(.proposed), actions: silenceActions)
                        SilenceFooterActions(presentation: BlitzUIKitSilence.presentation(.applied), actions: silenceActions)
                    }
                    .frame(width: 300)
                }
            }
            BlitzUIKitGroup("Settings previews · BlitzIllustratedLabel (hover animates)") {
                BlitzUIKitSpecimen(label: "BlitzIllustratedLabel") {
                    BlitzIllustratedLabel(configuration: .init(title: "Smooth cursor", detail: "Glide between clicks") { animating in
                        EditorMotionPreview(configuration: .init(effect: .smoothing(true),
                                                                 source: .init(screen: nil, camera: nil, background: .graphite),
                                                                 isAnimating: animating))
                    })
                    .frame(width: 300)
                }
            }
        }
    }

    private var silenceActions: SilencePaneActions {
        .init(apply: {}, restore: {}, setPreview: { _ in }, selectStrength: { _ in })
    }
}

struct BlitzUIKitPopovers: View {
    var body: some View {
        BlitzUIKitSection(title: "Popovers", detail: "Popover content, shown inline.") {
            BlitzUIKitGroup("Editor") {
                BlitzUIKitSpecimen(label: "EditorShortcutHelp · keyboard button in timeline header, or ?") {
                    EditorShortcutHelp()
                        .background(BlitzUI.panelBackground, in: .rect(cornerRadius: BlitzUI.cardRadius))
                }
            }
        }
    }
}

struct BlitzUIKitRecording: View {
    var body: some View {
        BlitzUIKitSection(title: "Recording", detail: "Dock, HUD and saved-take controls.") {
            BlitzUIKitGroup("Dock & HUD") {
                BlitzUIKitSpecimen(label: "DockActionButton") {
                    DockActionButton(title: "Pause", systemImage: "pause.fill", action: {})
                }
                BlitzUIKitSpecimen(label: "RecordingHUDIconButton · enabled / disabled") {
                    HStack {
                        RecordingHUDIconButton(configuration: .init(symbol: "stop.fill", fill: BlitzUI.recordRed, help: "",
                                                                    isEnabled: true, action: {}))
                        RecordingHUDIconButton(configuration: .init(symbol: "pause.fill", fill: BlitzUI.strongFill, help: "",
                                                                    isEnabled: false, action: {}))
                    }
                }
                BlitzUIKitSpecimen(label: "RecordingThumbnailButton · no image") {
                    RecordingThumbnailButton(image: nil, durationLabel: "05:17", help: "", action: {})
                }
            }
        }
    }
}

struct BlitzUIKitSharing: View {
    private let url = URL(string: "https://blitzreels.com/v/trailer")!

    var body: some View {
        BlitzUIKitSection(title: "Sharing & transcripts", detail: "Links, copy buttons, speaker labels.") {
            BlitzUIKitGroup("Links (click to see copied state)") {
                BlitzUIKitSpecimen(label: "HostedVideoLinkField · accent") {
                    HostedVideoLinkField(url: url, prominence: .accent).frame(width: 320)
                }
                BlitzUIKitSpecimen(label: "HostedVideoLinkField · secondary") {
                    HostedVideoLinkField(url: url, prominence: .secondary).frame(width: 320)
                }
                BlitzUIKitSpecimen(label: "HostedVideoLinkActions") { HostedVideoLinkActions(url: url) }
            }
            BlitzUIKitGroup("BlitzCopyButton (click to see copied state)") {
                BlitzUIKitSpecimen(label: "accent · large · fill") {
                    BlitzCopyButton(configuration: .watchLink(.init(url: url, title: "Copy link", emphasis: .accent, width: .fill)))
                        .controlSize(.large).frame(width: 260)
                }
                BlitzUIKitSpecimen(label: "secondary · fixed 84") {
                    BlitzCopyButton(configuration: .watchLink(.init(url: url, title: "Copy link", emphasis: .secondary, width: .fixed(84))))
                }
                BlitzUIKitSpecimen(label: "secondary · fit") {
                    BlitzCopyButton(configuration: .init(text: "# trailer", title: "Copy", accessibilityLabel: "Copy transcript",
                                                         help: "Copy", emphasis: .secondary, width: .fit))
                }
                BlitzUIKitSpecimen(label: "dock · ProjectAIPromptButton") {
                    BlitzCopyButton(configuration: .init(text: "context", title: "Copy AI context", accessibilityLabel: "Copy AI context",
                                                         help: "Copy", emphasis: .dock, width: .fit))
                }
            }
            BlitzUIKitGroup("Transcript") {
                BlitzUIKitSpecimen(label: "TranscriptSpeakerLabel · click to rename") {
                    TranscriptSpeakerLabel(configuration: .init(
                        speaker: .init(id: "S1", name: "Virgile", context: ""), color: BlitzUI.mint, onRename: { _ in }
                    ))
                }
                BlitzUIKitSpecimen(label: "TranscriptTimestampButton · active / normal / disabled") {
                    HStack {
                        TranscriptTimestampButton(timestamp: "01:21", isEnabled: true, isActive: true, action: {})
                        TranscriptTimestampButton(timestamp: "02:04", isEnabled: true, isActive: false, action: {})
                        TranscriptTimestampButton(timestamp: "03:40", isEnabled: false, isActive: false, action: {})
                    }
                }
            }
        }
    }
}

struct BlitzUIKitSettings: View {
    var body: some View {
        BlitzUIKitSection(title: "Settings & identity", detail: "Page header, sections, rows, avatars, brand.") {
            BlitzUIKitGroup("Settings page parts") {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsPageHeader(.init(title: "Recording", detail: "Files and transcripts",
                                             status: .init(title: "Ready", isActive: true)))
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            SettingsRowLabel(.init(title: "Save recordings to", detail: "~/Movies/BlitzRecorder"))
                            Spacer()
                            Button("Change…") {}.blitzButton(.secondary)
                        }
                        .settingsRow()
                        SettingsRowDivider()
                        HStack {
                            SettingsRowLabel(.init(title: "Transcribe automatically", detail: "On-device, private"))
                            Spacer()
                            Toggle("Transcribe", isOn: .constant(true)).toggleStyle(.blitzSwitchOnly)
                        }
                        .settingsRow()
                    }
                    .settingsCard()
                    .settingsSection(.init(title: "Files", detail: "Where takes are saved", systemImage: "folder"))
                }
                .frame(width: 520)
            }
            BlitzUIKitGroup("Identity") {
                BlitzUIKitSpecimen(label: "BlitzMonogram · circle / square") {
                    HStack {
                        BlitzMonogram(configuration: .init(text: "VR", seed: "virgile", size: 36, isCircle: true))
                        BlitzMonogram(configuration: .init(text: "AI", seed: "algomax", size: 36, isCircle: false))
                    }
                }
                BlitzUIKitSpecimen(label: "BlitzAccountAvatar · no image") {
                    BlitzAccountAvatar(configuration: .init(name: "Virgile Rietsch", imageURL: nil, size: 36))
                }
                BlitzUIKitSpecimen(label: "BlitzRemoteIcon · fallback") {
                    BlitzRemoteIcon(configuration: .init(name: "Claude", seed: "claude", imageURL: nil, size: 36, isCircle: false))
                }
                BlitzUIKitSpecimen(label: "BlitzReelsBrand") { BlitzReelsBrand() }
            }
        }
    }
}

struct BlitzUIKitLibraryParts: View {
    @State private var filters = ProjectLibraryFilters()
    @State private var folderName = "Module 02"

    var body: some View {
        BlitzUIKitSection(title: "Library parts", detail: "Thumbnails, filters, rename sheet.") {
            BlitzUIKitGroup("ProjectLibraryThumbnail") {
                BlitzUIKitSpecimen(label: "empty · with duration") {
                    ProjectLibraryThumbnail(configuration: .init(
                        metadata: .init(thumbnail: nil, durationSeconds: 317, sourceSummary: "", sizeBytes: nil,
                                        videoQuality: nil, sourceRoles: []),
                        width: 160, height: 90, cornerRadius: BlitzUI.controlRadius, showsDuration: true
                    ))
                }
                BlitzUIKitSpecimen(label: "empty · no duration") {
                    ProjectLibraryThumbnail(configuration: .init(metadata: .empty, width: 96, height: 54,
                                                                 cornerRadius: 6, showsDuration: false))
                }
            }
            BlitzUIKitGroup("Sheets & popovers (inline)") {
                BlitzUIKitSpecimen(label: "ProjectLibraryFiltersView") {
                    ProjectLibraryFiltersView(filters: $filters)
                        .frame(width: 300)
                        .background(BlitzUI.panelBackground, in: .rect(cornerRadius: BlitzUI.cardRadius))
                }
                BlitzUIKitSpecimen(label: "ProjectFolderNameEditor · rename") {
                    ProjectFolderNameEditor(prompt: .rename(ProjectFolderPath(["Formation IA", "Module 01"])!),
                                            name: $folderName, affectedCount: 4, onSave: {}, onCancel: {})
                        .background(BlitzUI.panelBackground, in: .rect(cornerRadius: BlitzUI.cardRadius))
                }
            }
        }
    }
}

struct BlitzUIKitUnused: View {
    var body: some View {
        BlitzUIKitSection(title: "Unused", detail: "Defined in code but never shown in the app. Candidates to delete or wire up.") {
            BlitzUIKitGroup("Views") {
                BlitzUIKitSpecimen(label: "ProjectLibraryIconActionButton · secondary / destructive") {
                    HStack {
                        ProjectLibraryIconActionButton(configuration: .init(title: "Reveal", systemImage: "folder",
                                                                            tone: .secondary, action: {}))
                        ProjectLibraryIconActionButton(configuration: .init(title: "Delete", systemImage: "trash",
                                                                            tone: .destructive, action: {}))
                    }
                }
                BlitzUIKitSpecimen(label: ".blitzSelectedSurface(isSelected:) · on / off") {
                    HStack {
                        Text("Selected").padding(10).blitzSelectedSurface(isSelected: true)
                        Text("Normal").padding(10).blitzSelectedSurface(isSelected: false)
                    }
                }
            }
            BlitzUIKitGroup("Tokens") {
                BlitzUIKitSpecimen(label: "BlitzUI.orange") {
                    RoundedRectangle(cornerRadius: BlitzUI.controlRadius).fill(BlitzUI.orange).frame(width: 116, height: 44)
                }
                ForEach([("BlitzSymbols.layers", BlitzSymbols.layers), ("BlitzSymbols.canvas", BlitzSymbols.canvas),
                         ("BlitzSymbols.source", BlitzSymbols.source), ("ProjectLibrarySymbols.media", ProjectLibrarySymbols.media)],
                        id: \.0) { name, symbol in
                    BlitzUIKitSpecimen(label: name) { BlitzIconTile(symbolName: symbol, isSelected: false, size: 32) }
                }
            }
        }
    }
}
#endif

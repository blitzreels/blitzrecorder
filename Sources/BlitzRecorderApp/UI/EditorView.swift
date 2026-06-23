import AppKit
import AVFoundation
import AVKit
import CoreImage
import QuartzCore
import SwiftUI

struct EditorView: View {
    @Bindable var vm: RecorderViewModel
    @State private var library = EditorMediaLibrary()
    @State private var playback = EditorPlaybackController()
    @State private var assets: [EditorAsset] = []
    @State private var selection: EditorSelection?
    @State private var selectedFormat: OutputVideoFormat = .mov
    @State private var reloadTask: Task<Void, Never>?
    @State private var sceneEvents: [RecordingSceneEvent] = []
    @State private var layoutDraft: EditorLayoutDraft?
    @State private var draftPreviewImages: [String: CGImage] = [:]
    @State private var editErrorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)

            if vm.state == .finishing {
                editorExportProgressBar
            }

            divider

            HStack(spacing: 0) {
                mediaBin
                    .frame(width: 232)
                    .background(.regularMaterial)

                verticalDivider

                playerColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(BlitzUI.canvasBackground)

                verticalDivider

                inspector
                    .frame(width: 280)
                    .background(.regularMaterial)
            }
            .frame(maxHeight: .infinity)

            divider

            EditorTimelineView(
                project: vm.lastExportedProject,
                assets: assets,
                library: library,
                duration: timelineDuration,
                playbackTime: playback.currentTime,
                liveTime: { playback.displayTime() },
                isPlaying: playback.isPlaying,
                selection: $selection,
                onSeek: { playback.scrub(to: $0) },
                onSeekEnded: { playback.endScrub() },
                isInteractive: playback.isReady,
                hiddenAssetIDs: hiddenAssetIDs,
                mutedAssetIDs: mutedAssetIDs,
                toggleableAssetIDs: toggleableAssetIDs,
                onToggleTrack: { toggleTrack($0) }
            )
            .padding(10)
            .background(BlitzUI.canvasBackground)
        }
        .task(id: vm.lastExportedSourceTakeURL) {
            vm.refreshLastExportedProject()
            reloadTask?.cancel()
            let task = Task { await reloadProject() }
            reloadTask = task
            await task.value
        }
        .onChange(of: vm.lastExportedProject) {
            reloadTask?.cancel()
            let task = Task {
                await reloadProject()
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled else { return }
                layoutDraft = nil
                draftPreviewImages = [:]
            }
            reloadTask = task
        }
        .onDisappear {
            reloadTask?.cancel()
            reloadTask = nil
            playback.teardown()
        }
        .overlay {
            EditorKeyboardShortcutView { event in
                handleKeyboardShortcut(event)
            }
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
        }
    }

    private func reloadProject() async {
        guard !Task.isCancelled else { return }
        guard let project = vm.lastExportedProject else {
            assets = []
            sceneEvents = []
            draftPreviewImages = [:]
            return
        }
        sceneEvents = TakeFileStore().sceneEvents(from: project)
        if let raw = OutputVideoFormat(rawValue: project.settings.outputVideoFormat) {
            selectedFormat = raw
        } else {
            selectedFormat = vm.settings.outputVideoFormat
        }
        assets = EditorAsset.assets(project: project, finalVideoURL: vm.lastExportedURL)
        async let media: Void = library.loadAssets(assets)
        await playback.load(project: project, baseSettings: vm.settings)
        await media
    }


    private var project: RecordingProject? {
        vm.lastExportedProject
    }

    private var timelineDuration: Double {
        if playback.duration > 0 {
            return playback.duration
        }
        let lastEvent = project?.sceneEvents.last?.time ?? 0
        return lastEvent > 0 ? lastEvent + 1 : 0
    }

    private var captureLayout: CaptureLayout? {
        project.flatMap { CaptureLayout(rawValue: $0.settings.layout) }
    }

    private var canvasAspectRatio: CGFloat {
        if playback.renderSize.width > 0, playback.renderSize.height > 0 {
            return playback.renderSize.width / playback.renderSize.height
        }
        return captureLayout?.aspectRatio ?? 16.0 / 9.0
    }

    private var ratioLabel: String {
        switch captureLayout {
        case .vertical: return "9:16"
        case .horizontal: return "16:9"
        case nil: return "—"
        }
    }

    private var resolutionLabel: String {
        guard let project,
              let resolution = OutputResolution(rawValue: project.settings.outputResolution) else {
            return "—"
        }
        if let captureLayout {
            let size = resolution.dimensions(for: captureLayout)
            return "\(size.width) × \(size.height)"
        }
        return resolution.displayName
    }

    private var segmentBoundaries: [Double] {
        (project?.sceneEvents.map(\.time) ?? []).sorted()
    }

    private var hiddenAssetIDs: Set<String> {
        Set(assets.filter { asset in
            layerKind(for: asset).map(playback.hiddenKinds.contains) ?? false
        }.map(\.id))
    }

    private var mutedAssetIDs: Set<String> {
        Set(assets.filter { asset in
            audioSource(for: asset).map(playback.mutedSources.contains) ?? false
        }.map(\.id))
    }

    private var toggleableAssetIDs: Set<String> {
        Set(assets.filter { asset in
            if let kind = layerKind(for: asset) {
                guard playback.hideableKinds.contains(kind) else { return false }
                let visibleVideoCount = playback.hideableKinds.subtracting(playback.hiddenKinds).count
                return playback.hiddenKinds.contains(kind) || visibleVideoCount > 1
            }
            if let source = audioSource(for: asset) {
                return playback.muteableSources.contains(source)
            }
            return false
        }.map(\.id))
    }

    private func layerKind(for asset: EditorAsset) -> SceneLayerKind? {
        switch asset.kind {
        case .screen: return .screen
        case .camera: return .camera
        default: return nil
        }
    }

    private func audioSource(for asset: EditorAsset) -> CaptureSource? {
        switch asset.kind {
        case .microphone: return .microphone
        case .systemAudio: return .systemAudio
        default: return nil
        }
    }

    private func toggleTrack(_ asset: EditorAsset) {
        if let kind = layerKind(for: asset) {
            playback.setHidden(!playback.hiddenKinds.contains(kind), kind: kind)
        } else if let source = audioSource(for: asset) {
            playback.setMuted(!playback.mutedSources.contains(source), source: source)
        }
    }

    private func asset(for kind: SceneLayerKind) -> EditorAsset? {
        switch kind {
        case .screen: return assets.first { $0.kind == .screen }
        case .camera: return assets.first { $0.kind == .camera }
        }
    }


    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(project?.title ?? "Last recording")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                Text(toolbarSubtitle)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            settingsChips

            Spacer(minLength: 12)

            Button {
                vm.revealLastExportOrSource()
            } label: {
                Label("Show in Finder", systemImage: "folder")
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .disabled(project == nil)
            .pointingHandCursor()

            editorExportControls
        }
    }

    private var toolbarSubtitle: String {
        if let project {
            return project.updatedAt.formatted(date: .abbreviated, time: .shortened)
        }
        return "Editable project"
    }

    private var settingsChips: some View {
        HStack(spacing: 6) {
            settingsChip(project.flatMap { OutputResolution(rawValue: $0.settings.outputResolution)?.displayName } ?? "—")
            settingsChip("\(project?.settings.framesPerSecond ?? vm.settings.framesPerSecond) FPS")
        }
    }

    private func settingsChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.66))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(BlitzUI.controlFill, in: .capsule)
    }

    private var editorExportControls: some View {
        HStack(spacing: 10) {
            exportQualityMenu
            exportButton
        }
    }

    private var exportQualityMenu: some View {
        BlitzGlassMenu(
            entries: OutputVideoFormat.allCases.map { format in
                .item(BlitzMenuItem(
                    title: format.displayName,
                    subtitle: format.plainDescription,
                    systemImage: format == .mp4 ? "paperplane.fill" : "film",
                    isSelected: format == selectedFormat
                ) {
                    selectedFormat = format
                })
            },
            menuWidth: 260
        ) {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BlitzUI.mint)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Quality")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.45))
                    Text(qualitySummary)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                        .monospacedDigit()
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(BlitzUI.controlFill, in: .rect(cornerRadius: 10))
        }
        .pointingHandCursor()
        .help(selectedFormat.plainDescription)
    }

    private var exportButton: some View {
        Button {
            vm.exportLastProject(
                as: selectedFormat,
                hiddenVideoSources: playback.hiddenKinds,
                mutedAudioSources: playback.mutedSources
            )
        } label: {
            HStack(spacing: 10) {
                Image(systemName: vm.state == .finishing ? "hourglass" : "square.and.arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(BlitzUI.mint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(vm.state == .finishing ? "Exporting" : "Export")
                        .font(.system(size: 13, weight: .heavy))
                    Text(selectedFormat.displayName)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.68))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .frame(minWidth: 132)
        }
        .buttonStyle(.plain)
        .background(BlitzUI.selectedFill, in: .rect(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(BlitzUI.mint.opacity(0.35), lineWidth: 1)
        }
        .pointingHandCursor()
        .disabled(project == nil || vm.state != .idle)
        .opacity(project == nil ? 0.45 : 1)
        .help("Export this edit as \(selectedFormat.displayName)")
    }

    private var qualitySummary: String {
        "\(selectedFormat.displayName) · \(resolutionLabel) · \(project?.settings.framesPerSecond ?? vm.settings.framesPerSecond) FPS"
    }

    private var editorExportProgressBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.up.doc.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BlitzUI.mint)
                .frame(width: 22, height: 22)
                .background(BlitzUI.mint.opacity(0.14), in: .rect(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(vm.sessionProgressTitle.isEmpty ? "Exporting" : vm.sessionProgressTitle)
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.86))
                    Text(vm.sessionProgressLabel)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.68))
                    if let detail = vm.sessionProgressDetail {
                        Text(detail)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.48))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                ProgressView(value: vm.sessionProgressValue)
                    .progressViewStyle(.linear)
                    .tint(BlitzUI.mint)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.22))
    }


    private var mediaBin: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                BlitzUI.sectionLabel("Media", icon: "tray.full")
                    .padding(.top, 12)

                if assets.isEmpty {
                    Text("No media for this recording yet.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.vertical, 8)
                } else {
                    ForEach(assets) { asset in
                        mediaBinCard(asset)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
    }

    private func mediaBinCard(_ asset: EditorAsset) -> some View {
        let isSelected = selection == .asset(asset.id)
        return Button {
            selection = .asset(asset.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                mediaBinThumbnail(asset)

                HStack(spacing: 6) {
                    Image(systemName: asset.systemImage)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(isSelected ? BlitzUI.mint : .white.opacity(0.5))
                        .frame(width: 13)
                    Text(asset.title)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(mediaBinCaption(asset))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
            .padding(7)
        }
        .buttonStyle(.plain)
        .blitzSelectedSurface(isSelected: isSelected, cornerRadius: 9)
        .pointingHandCursor()
        .help(asset.url.path)
    }

    @ViewBuilder
    private func mediaBinThumbnail(_ asset: EditorAsset) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.4))

            if let poster = library.posters[asset.id] {
                Image(decorative: poster, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else if asset.isAudio {
                EditorWaveformBadge(samples: library.waveforms[asset.id] ?? [], tint: asset.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            } else {
                Image(systemName: asset.exists ? asset.systemImage : "exclamationmark.triangle")
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(asset.exists ? .white.opacity(0.35) : BlitzUI.warning)
            }
        }
        .frame(height: 72)
        .clipShape(.rect(cornerRadius: 6))
        .overlay(alignment: .bottomTrailing) {
            if let duration = library.durations[asset.id] {
                Text(formatTime(duration))
                    .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.55), in: .capsule)
                    .padding(4)
            }
        }
    }

    private func mediaBinCaption(_ asset: EditorAsset) -> String {
        guard asset.exists else { return "Missing" }
        return library.fileSizes[asset.id] ?? ""
    }


    private var playerColumn: some View {
        VStack(spacing: 10) {
            canvasStage
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            transportBar
        }
        .padding(14)
    }

    private var canvasStage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black)

            if playback.isReady {
                EditorPlayerView(player: playback.player, redrawID: playback.previewRevision)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(.rect(cornerRadius: 12))
                    .opacity(layoutDraft == nil ? 1 : 0)
                    .allowsHitTesting(false)
            }

            if let draft = layoutDraft {
                EditorCanvasSourcePreviewOverlay(
                    scene: draft.scene,
                    assetsByID: Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) }),
                    previewImages: draftPreviewImages,
                    library: library
                )
                .clipShape(.rect(cornerRadius: 12))
                .allowsHitTesting(false)
            }

            if playback.isReady {
                EditorCanvasLayerOverlay(
                    layers: displayedCanvasLayers,
                    onSelect: { layer in
                        if let id = layer.assetID {
                            selection = .asset(id)
                        }
                    },
                    onMove: { kind, translation, ended in
                        handleLayerMove(kind: kind, translation: translation, ended: ended)
                    },
                    onResize: { kind, anchor, translation, ended in
                        handleLayerResize(kind: kind, anchor: anchor, translation: translation, ended: ended)
                    }
                )
            } else if layoutDraft == nil, let error = playback.loadError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(BlitzUI.warning)
                    Text("The preview could not be built.")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                    Text(error)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            } else if layoutDraft == nil {
                Color.clear
            }
        }
        .aspectRatio(canvasAspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transaction { transaction in
            transaction.animation = nil
        }
        .overlay(alignment: .top) {
            Text(ratioLabel)
                .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white.opacity(0.78))
                .padding(.horizontal, 9)
                .padding(.vertical, 3.5)
                .background(Color.black.opacity(0.55), in: .capsule)
                .padding(.top, 8)
        }
        .overlay(alignment: .bottom) {
            if let editErrorMessage {
                Label(editErrorMessage, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BlitzUI.warning)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.65), in: .capsule)
                    .padding(.bottom, 10)
                    .transition(.opacity)
                    .task {
                        try? await Task.sleep(for: .seconds(4))
                        self.editErrorMessage = nil
                    }
            }
        }
    }

    private var transportBar: some View {
        HStack(spacing: 12) {
            Text("\(formatTime(playback.currentTime)) / \(formatTime(timelineDuration))")
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.62))
                .frame(minWidth: 92, alignment: .leading)

            Spacer(minLength: 0)

            transportButton("backward.end.fill", help: "Previous segment") {
                playback.seek(to: previousBoundary())
            }

            playPauseButton

            transportButton("forward.end.fill", help: "Next segment") {
                playback.seek(to: nextBoundary())
            }

            Spacer(minLength: 0)

            Color.clear
                .frame(minWidth: 92, maxWidth: 92, maxHeight: 1)
        }
    }

    @ViewBuilder
    private var playPauseButton: some View {
        let button = Button {
            playback.togglePlayback()
        } label: {
            Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(playback.isReady ? 0.95 : 0.35))
                .frame(width: 38, height: 30)
                .background(BlitzUI.selectedFill, in: .rect(cornerRadius: 8))
                .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!playback.isReady)
        .help(playback.isPlaying ? "Pause" : "Play")

        if playback.isReady {
            button.pointingHandCursor()
        } else {
            button
        }
    }

    @ViewBuilder
    private func transportButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        let button = Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(.white.opacity(playback.isReady ? 0.7 : 0.3))
                .frame(width: 30, height: 26)
                .background(BlitzUI.controlFill, in: .rect(cornerRadius: 7))
                .contentShape(.rect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(!playback.isReady)
        .help(help)

        if playback.isReady {
            button.pointingHandCursor()
        } else {
            button
        }
    }


    private var currentEventIndex: Int {
        let time = playback.currentTime
        var index = 0
        for (i, event) in sceneEvents.enumerated() where event.time <= time + 0.0001 {
            index = i
        }
        return index
    }

    private var currentEventScene: RecordingScene? {
        sceneEvents.indices.contains(currentEventIndex) ? sceneEvents[currentEventIndex].scene : nil
    }

    private func canEditLayout(of scene: RecordingScene) -> Bool {
        playback.isReady
            && scene.enabledSources.contains(.screen)
            && scene.enabledSources.contains(.camera)
    }

    private var displayedCanvasLayers: [EditorCanvasLayer] {
        let frames: [(kind: SceneLayerKind, frame: CGRect)]
        let editable: Bool
        if let draft = layoutDraft {
            frames = playback.layerFrames(for: draft.scene)
            editable = true
        } else {
            frames = playback.layerFrames(at: playback.currentTime)
            editable = currentEventScene.map(canEditLayout(of:)) ?? false
        }
        return frames.map { kind, frame in
            let asset = asset(for: kind)
            return EditorCanvasLayer(
                kind: kind,
                assetID: asset?.id,
                frame: frame,
                isSelected: asset.map { selection == .asset($0.id) } ?? false,
                isEditable: editable
            )
        }
    }

    private func ensureLayoutDraft() -> EditorLayoutDraft? {
        if let layoutDraft { return layoutDraft }
        playback.pauseForEditing()
        let index = currentEventIndex
        guard sceneEvents.indices.contains(index) else { return nil }
        let event = sceneEvents[index]
        guard canEditLayout(of: event.scene) else { return nil }
        let transitionEnd = event.time + event.transition.duration
        if playback.currentTime < transitionEnd {
            playback.seek(to: min(transitionEnd, timelineDuration))
        }
        let draft = EditorLayoutDraft(
            eventIndex: index,
            startLayout: event.scene.sceneLayout,
            scene: event.scene
        )
        prepareDraftPreviewImages(at: playback.currentTime)
        layoutDraft = draft
        return draft
    }

    private func prepareDraftPreviewImages(at seconds: Double) {
        var seeded = draftPreviewImages
        for asset in assets where asset.exists && asset.isVideo && layerKind(for: asset) != nil {
            if seeded[asset.id] == nil, let poster = library.posters[asset.id] {
                seeded[asset.id] = poster
            }
            Task {
                guard let image = await Self.previewImage(for: asset.url, at: seconds) else { return }
                await MainActor.run {
                    draftPreviewImages[asset.id] = image
                }
            }
        }
        draftPreviewImages = seeded
    }

    nonisolated private static func previewImage(for url: URL, at seconds: Double) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.12, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.12, preferredTimescale: 600)
        generator.maximumSize = CGSize(width: 1600, height: 1600)
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        return try? await generator.image(at: time).image
    }

    private func handleLayerMove(kind: SceneLayerKind, translation: CGSize, ended: Bool) {
        guard var draft = ensureLayoutDraft() else { return }
        if let asset = asset(for: kind) {
            selection = .asset(asset.id)
        }
        var frame = layoutFrame(kind, in: draft.startLayout)
        frame.origin.x += translation.width
        frame.origin.y -= translation.height
        setLayoutFrame(SceneLayerResizing.clamped(frame), kind: kind, in: &draft.scene.sceneLayout)
        layoutDraft = draft
        if ended {
            commitLayoutDraft(draft)
        }
    }

    private func handleLayerResize(kind: SceneLayerKind, anchor: ResizeAnchor, translation: CGSize, ended: Bool) {
        guard var draft = ensureLayoutDraft() else { return }
        let start = resizeStartFrame(kind: kind, draft: draft)
        let resized = SceneLayerResizing.resized(
            start,
            delta: CGPoint(x: translation.width, y: -translation.height),
            anchor: anchor,
            aspectRatio: start.height > 0 ? start.width / start.height : nil
        )
        setLayoutFrame(resized, kind: kind, in: &draft.scene.sceneLayout)
        layoutDraft = draft
        if ended {
            commitLayoutDraft(draft)
        }
    }

    private func resizeStartFrame(kind: SceneLayerKind, draft: EditorLayoutDraft) -> CGRect {
        guard kind == .camera, draft.scene.cameraContentMode == .fit else {
            return layoutFrame(kind, in: draft.startLayout)
        }
        var startScene = draft.scene
        startScene.sceneLayout = draft.startLayout
        guard let visibleFrame = playback.layerFrames(for: startScene).first(where: { $0.kind == kind })?.frame else {
            return layoutFrame(kind, in: draft.startLayout)
        }
        return layoutFrame(fromUpperLeftNormalizedFrame: visibleFrame)
    }

    private func layoutFrame(fromUpperLeftNormalizedFrame frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX,
            y: 1 - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    private func commitLayoutDraft(_ draft: EditorLayoutDraft) {
        guard draft.scene.sceneLayout != draft.startLayout else {
            layoutDraft = nil
            draftPreviewImages = [:]
            playback.setPreviewSceneOverride(nil, at: playback.currentTime)
            return
        }
        let before = vm.lastExportedProject
        let succeeded = vm.applyProjectSceneEdit(eventIndex: draft.eventIndex) {
            $0.sceneLayout = draft.scene.sceneLayout
        }
        if !succeeded {
            layoutDraft = nil
            draftPreviewImages = [:]
            playback.setPreviewSceneOverride(nil, at: playback.currentTime)
            editErrorMessage = "The layout change could not be saved."
        } else if vm.lastExportedProject == before {
            layoutDraft = nil
            draftPreviewImages = [:]
            playback.setPreviewSceneOverride(nil, at: playback.currentTime)
        }
    }

    private func layoutFrame(_ kind: SceneLayerKind, in layout: SceneLayout) -> CGRect {
        kind == .screen ? layout.screenFrame : layout.cameraFrame
    }

    private func setLayoutFrame(_ frame: CGRect, kind: SceneLayerKind, in layout: inout SceneLayout) {
        if kind == .screen {
            layout.screenFrame = frame
        } else {
            layout.cameraFrame = frame
        }
    }

    private func previousBoundary() -> Double {
        let boundaries = segmentBoundaries.filter { $0 < playback.currentTime - 0.25 }
        return boundaries.last ?? 0
    }

    private func nextBoundary() -> Double {
        let boundaries = segmentBoundaries.filter { $0 > playback.currentTime + 0.25 }
        return boundaries.first ?? timelineDuration
    }

    @discardableResult
    private func handleKeyboardShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasCommand = flags.contains(.command)
        let hasOption = flags.contains(.option)
        let hasControl = flags.contains(.control)
        let hasShift = flags.contains(.shift)
        let key = event.charactersIgnoringModifiers?.lowercased()

        if hasCommand {
            guard !hasOption, !hasControl, key == "b" else { return false }
            splitAtPlayhead()
            return true
        }
        guard !hasOption, !hasControl else { return false }

        switch event.keyCode {
        case 49:
            playback.togglePlayback()
            return true
        case 123:
            hasShift ? playback.seek(by: -1) : playback.step(byFrames: -1)
            return true
        case 124:
            hasShift ? playback.seek(by: 1) : playback.step(byFrames: 1)
            return true
        case 125:
            playback.seek(to: nextBoundary())
            return true
        case 126:
            playback.seek(to: previousBoundary())
            return true
        case 51, 117:
            deleteSelectedCut()
            return true
        default:
            break
        }

        switch key {
        case "b", "s":
            splitAtPlayhead()
            return true
        case "h", "m":
            return toggleSelectedAsset()
        default:
            return false
        }
    }

    private func splitAtPlayhead() {
        guard playback.isReady else { return }
        layoutDraft = nil
        playback.setPreviewSceneOverride(nil, at: playback.currentTime)
        let insertIndex = sceneEvents.filter { $0.time < playback.currentTime }.count
        if vm.splitProjectScene(at: playback.currentTime, duration: timelineDuration) {
            selection = .segment(max(0, insertIndex))
        } else {
            editErrorMessage = vm.detailMessage
        }
    }

    private func deleteSelectedCut() {
        guard case .segment(let index) = selection else {
            editErrorMessage = "Select a segment cut to remove."
            return
        }
        if vm.removeProjectSceneEvent(eventIndex: index) {
            selection = .segment(max(0, index - 1))
        } else {
            editErrorMessage = vm.detailMessage
        }
    }

    @discardableResult
    private func toggleSelectedAsset() -> Bool {
        guard case .asset(let id) = selection,
              let asset = assets.first(where: { $0.id == id }),
              toggleableAssetIDs.contains(asset.id) else {
            return false
        }
        toggleTrack(asset)
        return true
    }


    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                detailsSection

                switch selection {
                case .segment(let index):
                    segmentSection(index: index)
                case .asset(let id):
                    if let asset = assets.first(where: { $0.id == id }) {
                        assetSection(asset)
                    }
                case nil:
                    EmptyView()
                }
            }
            .padding(12)
        }
        .scrollIndicators(.hidden)
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            BlitzUI.sectionLabel("Details", icon: "info.circle")

            VStack(alignment: .leading, spacing: 7) {
                detailRow("Name", project?.title ?? "—")
                detailRow("Saved", project?.takeDirectoryPath ?? "—", monospaced: true)
                detailRow("Resolution", resolutionLabel)
                detailRow("Ratio", ratioLabel)
                detailRow("FPS", "\(project?.settings.framesPerSecond ?? 0)")
                detailRow("Duration", timelineDuration > 0 ? formatTime(timelineDuration) : "—")
                detailRow("Sources", "\(project?.sources.filter(\.exists).count ?? 0)")
            }
            .padding(10)
            .background(BlitzUI.quietFill, in: .rect(cornerRadius: 9))
        }
    }

    private func detailRow(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 66, alignment: .leading)
            Text(value)
                .font(.system(size: monospaced ? 9.5 : 11, weight: .semibold, design: monospaced ? .monospaced : .default))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(monospaced ? 2 : 1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(value)
        }
    }

    private func segmentSection(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            BlitzUI.sectionLabel("Segment \(index + 1)", icon: "rectangle.on.rectangle")

            if let events = project?.sceneEvents, events.indices.contains(index) {
                let event = events[index]
                let end = index + 1 < events.count ? events[index + 1].time : timelineDuration
                Text("\(formatTime(event.time)) – \(formatTime(end))")
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.55))

                VStack(spacing: 6) {
                    ForEach(RecordingProjectSceneCorrection.allCases, id: \.self) { correction in
                        correctionButton(
                            correction,
                            isSelected: correction == selectedCorrection(for: event)
                        ) {
                            vm.applyProjectSceneCorrection(eventIndex: index, correction: correction)
                        }
                    }
                }
                Text("The preview and the export both re-render with the new mix.")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
            }
        }
    }

    private func correctionButton(
        _ correction: RecordingProjectSceneCorrection,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: correction.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? BlitzUI.mint : .white.opacity(0.56))
                    .frame(width: 16, height: 16)
                Text(correctionTitle(correction))
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(BlitzUI.mint)
                }
            }
            .foregroundStyle(isSelected ? .white.opacity(0.92) : .white.opacity(0.68))
            .frame(maxWidth: .infinity, minHeight: 32)
            .padding(.horizontal, 9)
        }
        .buttonStyle(.plain)
        .blitzSelectedSurface(isSelected: isSelected, cornerRadius: 8)
        .contentShape(.rect(cornerRadius: 8))
        .pointingHandCursor()
    }

    private func correctionTitle(_ correction: RecordingProjectSceneCorrection) -> String {
        switch correction {
        case .screenOnly: return "Screen"
        case .cameraOnly: return "Camera"
        case .screenAndCamera: return "Screen + Camera"
        }
    }

    private func selectedCorrection(for event: RecordingProject.SceneEventSnapshot) -> RecordingProjectSceneCorrection {
        let sources = Set(event.scene.enabledSources.compactMap(CaptureSource.init(rawValue:)))
        let hasScreen = sources.contains(.screen)
        let hasCamera = sources.contains(.camera)
        switch (hasScreen, hasCamera) {
        case (true, false): return .screenOnly
        case (false, true): return .cameraOnly
        default: return .screenAndCamera
        }
    }

    private func assetSection(_ asset: EditorAsset) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            BlitzUI.sectionLabel(asset.title, icon: asset.systemImage)

            VStack(alignment: .leading, spacing: 7) {
                detailRow("File", asset.url.lastPathComponent, monospaced: true)
                detailRow("Size", asset.exists ? (library.fileSizes[asset.id] ?? "—") : "Missing")
                detailRow("Length", library.durations[asset.id].map(formatTime) ?? "—")
            }
            .padding(10)
            .background(BlitzUI.quietFill, in: .rect(cornerRadius: 9))

            HStack(spacing: 7) {
                if toggleableAssetIDs.contains(asset.id) {
                    let isOff = hiddenAssetIDs.contains(asset.id) || mutedAssetIDs.contains(asset.id)
                    Button {
                        toggleTrack(asset)
                    } label: {
                        Label(
                            asset.isVideo ? (isOff ? "Show" : "Hide") : (isOff ? "Unmute" : "Mute"),
                            systemImage: asset.isVideo
                                ? (isOff ? "eye" : "eye.slash")
                                : (isOff ? "speaker.wave.2" : "speaker.slash")
                        )
                        .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .pointingHandCursor()
                }
                if asset.exists {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([asset.url])
                    } label: {
                        Label("Show in Finder", systemImage: "folder")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .pointingHandCursor()
                }
            }

            if asset.kind == .camera, currentEventScene != nil {
                cameraFrameSection
            }
        }
    }

    @ViewBuilder
    private var cameraFrameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            BlitzUI.sectionLabel("Camera frame", icon: "video")

            if sceneEvents.count > 1 {
                Text("Applies to segment \(currentEventIndex + 1)")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
            }

            CameraInspectorRow(title: "Image") {
                Picker("Image", selection: segmentSceneBinding(\.cameraContentMode, fallback: .fill)) {
                    ForEach(CameraContentMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
            }
            .help("Fill the frame edge to edge, or fit the whole camera image")

            Toggle(isOn: segmentSceneBinding(\.cameraShadowEnabled, fallback: false)) {
                Label("Shadow", systemImage: "square.stack.3d.down.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(BlitzUI.mint)
            .help("Add a soft shadow under the camera")

            Text("Drag the camera in the canvas to move it; drag a corner to resize.")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
        }
    }

    private func segmentSceneBinding<Value>(
        _ keyPath: WritableKeyPath<RecordingScene, Value>,
        fallback: Value
    ) -> Binding<Value> {
        let index = currentEventIndex
        let value = currentEventScene?[keyPath: keyPath] ?? fallback
        return Binding(
            get: { value },
            set: { newValue in
                vm.applyProjectSceneEdit(eventIndex: index) { $0[keyPath: keyPath] = newValue }
            }
        )
    }


    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    private var divider: some View {
        Rectangle()
            .fill(BlitzUI.separator)
            .frame(height: 1)
    }

    private var verticalDivider: some View {
        Rectangle()
            .fill(BlitzUI.separator)
            .frame(width: 1)
    }
}

private struct EditorLayoutDraft {
    let eventIndex: Int
    let startLayout: SceneLayout
    var scene: RecordingScene
}

private struct EditorCanvasLayer: Identifiable {
    let kind: SceneLayerKind
    let assetID: String?
    let frame: CGRect      // normalized 0...1, top-left origin
    let isSelected: Bool
    let isEditable: Bool

    var id: String { kind.rawValue }
}

private let editorCanvasSpace = "EditorCanvasOverlay"

private struct EditorCanvasLayerOverlay: View {
    let layers: [EditorCanvasLayer]
    let onSelect: (EditorCanvasLayer) -> Void
    let onMove: (SceneLayerKind, CGSize, Bool) -> Void
    let onResize: (SceneLayerKind, ResizeAnchor, CGSize, Bool) -> Void
    @State private var hoveredLayerID: String?

    var body: some View {
        GeometryReader { proxy in
            ForEach(layers) { layer in
                EditorCanvasLayerView(
                    layer: layer,
                    isHovering: hoveredLayerID == layer.id
                )
                .frame(
                    width: layer.frame.width * proxy.size.width,
                    height: layer.frame.height * proxy.size.height
                )
                .offset(
                    x: layer.frame.minX * proxy.size.width,
                    y: layer.frame.minY * proxy.size.height
                )
                .allowsHitTesting(false)
            }

            EditorCanvasInteractionView(
                layers: layers,
                hoveredLayerID: $hoveredLayerID,
                onSelect: onSelect,
                onMove: { kind, translation, ended in
                    onMove(kind, normalized(translation, in: proxy.size), ended)
                },
                onResize: { kind, anchor, translation, ended in
                    onResize(kind, anchor, normalized(translation, in: proxy.size), ended)
                }
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .coordinateSpace(name: editorCanvasSpace)
    }

    private func normalized(_ translation: CGSize, in size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        return CGSize(width: translation.width / size.width, height: translation.height / size.height)
    }
}

private struct EditorCanvasSourcePreviewOverlay: View {
    let scene: RecordingScene
    let assetsByID: [String: EditorAsset]
    let previewImages: [String: CGImage]
    let library: EditorMediaLibrary

    var body: some View {
        GeometryReader { proxy in
            let canvas = CGRect(origin: .zero, size: proxy.size)
            let geometry = SceneRenderGeometry(canvas: canvas, scene: scene, origin: .upperLeft)

            EditorCanvasBackgroundView(style: scene.canvasBackgroundStyle)
                .frame(width: proxy.size.width, height: proxy.size.height)

            ForEach(geometry.activeLayerOrder, id: \.self) { kind in
                if let asset = asset(for: kind), let image = image(for: asset) {
                    sourceView(kind: kind, image: image, geometry: geometry)
                }
            }
        }
    }

    private func asset(for kind: SceneLayerKind) -> EditorAsset? {
        switch kind {
        case .screen:
            return assetsByID.values.first { $0.kind == .screen }
        case .camera:
            return assetsByID.values.first { $0.kind == .camera }
        }
    }

    private func image(for asset: EditorAsset) -> CGImage? {
        previewImages[asset.id] ?? library.posters[asset.id]
    }

    private func sourceView(kind: SceneLayerKind, image: CGImage, geometry: SceneRenderGeometry) -> some View {
        let placement = geometry.videoPlacement(for: kind)
        let target = placement.targetRect
        let aspectRatio = CGFloat(image.width) / max(1, CGFloat(image.height))
        let sourceFrame = placement.sourceFrame(sourceAspectRatio: aspectRatio)
        let radius = geometry.sourceCornerRadius(for: kind)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        return ZStack(alignment: .topLeading) {
            Image(decorative: image, scale: 1)
                .resizable()
                .frame(width: sourceFrame.width, height: sourceFrame.height)
                .offset(x: sourceFrame.minX - target.minX, y: sourceFrame.minY - target.minY)
        }
        .frame(width: target.width, height: target.height, alignment: .topLeading)
        .clipShape(shape)
        .offset(x: target.minX, y: target.minY)
    }
}

private struct EditorCanvasBackgroundView: View {
    let style: CanvasBackgroundStyle

    var body: some View {
        Color(cgColor: style.appearance.solidCGColor)
    }
}

private struct EditorCanvasLayerView: View {
    let layer: EditorCanvasLayer
    let isHovering: Bool

    var body: some View {
        ZStack {
            if layer.isSelected {
                Rectangle()
                    .stroke(BlitzUI.mint, lineWidth: 1.5)
            } else if isHovering {
                Rectangle()
                    .stroke(BlitzUI.mint.opacity(0.82), lineWidth: 1.25)
            }
        }
        .overlay {
            if layer.isSelected && layer.isEditable {
                resizeHandles
            }
        }
    }

    private var resizeHandles: some View {
        ZStack {
            handle(.topLeft, alignment: .topLeading)
            handle(.topRight, alignment: .topTrailing)
            handle(.bottomLeft, alignment: .bottomLeading)
            handle(.bottomRight, alignment: .bottomTrailing)
        }
    }

    private func handle(_ anchor: ResizeAnchor, alignment: Alignment) -> some View {
        let offsetX: CGFloat = alignment.horizontal == .leading ? -6 : 6
        let offsetY: CGFloat = alignment.vertical == .top ? -6 : 6
        return Rectangle()
            .fill(.clear)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: alignment) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(BlitzUI.mint)
                    .frame(width: 12, height: 12)
                    .overlay {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(Color.black.opacity(0.9), lineWidth: 1)
                    }
                    .padding(2)
                    .offset(x: offsetX, y: offsetY)
            }
    }
}

private struct EditorCanvasInteractionView: NSViewRepresentable {
    let layers: [EditorCanvasLayer]
    @Binding var hoveredLayerID: String?
    let onSelect: (EditorCanvasLayer) -> Void
    let onMove: (SceneLayerKind, CGSize, Bool) -> Void
    let onResize: (SceneLayerKind, ResizeAnchor, CGSize, Bool) -> Void

    func makeNSView(context: Context) -> InteractionView {
        let view = InteractionView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: InteractionView, context: Context) {
        update(nsView)
    }

    private func update(_ view: InteractionView) {
        view.layers = layers
        view.hoveredLayerID = hoveredLayerID
        view.onHover = { hoveredLayerID = $0 }
        view.onSelect = onSelect
        view.onMove = onMove
        view.onResize = onResize
        view.needsDisplay = true
    }

    final class InteractionView: NSView {
        enum DragMode {
            case move(SceneLayerKind)
            case resize(SceneLayerKind, ResizeAnchor)
        }

        var layers: [EditorCanvasLayer] = []
        var hoveredLayerID: String?
        var onHover: ((String?) -> Void)?
        var onSelect: ((EditorCanvasLayer) -> Void)?
        var onMove: ((SceneLayerKind, CGSize, Bool) -> Void)?
        var onResize: ((SceneLayerKind, ResizeAnchor, CGSize, Bool) -> Void)?
        private var trackingArea: NSTrackingArea?
        private var dragMode: DragMode?
        private var dragStart: CGPoint = .zero

        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                owner: self
            )
            trackingArea = area
            addTrackingArea(area)
        }

        override func mouseMoved(with event: NSEvent) {
            guard dragMode == nil else { return }
            let point = convert(event.locationInWindow, from: nil)
            setHoveredLayer(resizeHit(at: point)?.layer.id ?? hitLayer(at: point)?.id)
            cursor(at: point).set()
        }

        override func mouseExited(with event: NSEvent) {
            guard dragMode == nil else { return }
            setHoveredLayer(nil)
            NSCursor.arrow.set()
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            let point = convert(event.locationInWindow, from: nil)
            dragStart = point
            if let hit = resizeHit(at: point) {
                onSelect?(hit.layer)
                setHoveredLayer(hit.layer.id)
                dragMode = .resize(hit.layer.kind, hit.anchor)
                hit.anchor.cursor.set()
                return
            }
            guard let layer = hitLayer(at: point) else {
                dragMode = nil
                setHoveredLayer(nil)
                return
            }
            onSelect?(layer)
            setHoveredLayer(layer.id)
            if layer.isSelected, layer.isEditable, let anchor = resizeAnchor(at: point, in: layer) {
                dragMode = .resize(layer.kind, anchor)
                anchor.cursor.set()
            } else if layer.isEditable {
                dragMode = .move(layer.kind)
                NSCursor.closedHand.set()
            } else {
                dragMode = nil
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let dragMode else { return }
            let point = convert(event.locationInWindow, from: nil)
            let translation = CGSize(width: point.x - dragStart.x, height: point.y - dragStart.y)
            switch dragMode {
            case .move(let kind):
                onMove?(kind, translation, false)
            case .resize(let kind, let anchor):
                onResize?(kind, anchor, translation, false)
            }
        }

        override func mouseUp(with event: NSEvent) {
            guard let dragMode else { return }
            let point = convert(event.locationInWindow, from: nil)
            let translation = CGSize(width: point.x - dragStart.x, height: point.y - dragStart.y)
            switch dragMode {
            case .move(let kind):
                onMove?(kind, translation, true)
            case .resize(let kind, let anchor):
                onResize?(kind, anchor, translation, true)
            }
            self.dragMode = nil
            cursor(at: point).set()
        }

        private func hitLayer(at point: CGPoint) -> EditorCanvasLayer? {
            layers.reversed().first { frame(for: $0).contains(point) }
        }

        private func resizeHit(at point: CGPoint) -> (layer: EditorCanvasLayer, anchor: ResizeAnchor)? {
            for layer in layers.reversed() where layer.isSelected && layer.isEditable {
                if let anchor = resizeAnchor(at: point, in: layer) {
                    return (layer, anchor)
                }
            }
            return nil
        }

        private func frame(for layer: EditorCanvasLayer) -> CGRect {
            CGRect(
                x: layer.frame.minX * bounds.width,
                y: layer.frame.minY * bounds.height,
                width: layer.frame.width * bounds.width,
                height: layer.frame.height * bounds.height
            )
        }

        private func resizeAnchor(at point: CGPoint, in layer: EditorCanvasLayer) -> ResizeAnchor? {
            let frame = frame(for: layer)
            let size: CGFloat = 18
            let half = size / 2
            let handles: [(ResizeAnchor, CGRect)] = [
                (.topLeft, CGRect(x: frame.minX - half, y: frame.minY - half, width: size, height: size)),
                (.topRight, CGRect(x: frame.maxX - half, y: frame.minY - half, width: size, height: size)),
                (.bottomLeft, CGRect(x: frame.minX - half, y: frame.maxY - half, width: size, height: size)),
                (.bottomRight, CGRect(x: frame.maxX - half, y: frame.maxY - half, width: size, height: size))
            ]
            return handles.first { $0.1.contains(point) }?.0
        }

        private func cursor(at point: CGPoint) -> NSCursor {
            if let hit = resizeHit(at: point) {
                return hit.anchor.cursor
            }
            guard let layer = hitLayer(at: point) else { return .arrow }
            if layer.isSelected, layer.isEditable, let anchor = resizeAnchor(at: point, in: layer) {
                return anchor.cursor
            }
            return layer.isEditable ? .openHand : .pointingHand
        }

        private func setHoveredLayer(_ id: String?) {
            guard hoveredLayerID != id else { return }
            hoveredLayerID = id
            onHover?(id)
        }
    }
}

private struct EditorWaveformBadge: View {
    let samples: [Float]
    let tint: Color

    var body: some View {
        Canvas { context, size in
            let values = samples.isEmpty ? Array(repeating: Float(0.25), count: 48) : samples
            let barCount = min(values.count, 64)
            let stride = max(1, values.count / barCount)
            let slot = size.width / CGFloat(barCount)
            let barWidth = max(1, slot - 1)
            let centerY = size.height / 2
            for index in 0..<barCount {
                let value = CGFloat(values[min(index * stride, values.count - 1)])
                let height = max(1.5, value * size.height)
                let rect = CGRect(x: CGFloat(index) * slot, y: centerY - height / 2, width: barWidth, height: height)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(tint.opacity(samples.isEmpty ? 0.3 : 0.85))
                )
            }
        }
    }
}

private struct EditorPlayerView: NSViewRepresentable {
    let player: AVPlayer
    let redrawID: Int

    func makeNSView(context: Context) -> EditorPlayerLayerHostView {
        let view = EditorPlayerLayerHostView()
        view.player = player
        view.redrawID = redrawID
        return view
    }

    func updateNSView(_ nsView: EditorPlayerLayerHostView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
        if nsView.redrawID != redrawID {
            nsView.redrawID = redrawID
            nsView.invalidateFallbackFrame()
        }
    }

    static func dismantleNSView(_ nsView: EditorPlayerLayerHostView, coordinator: ()) {
        nsView.player = nil
    }
}

private final class EditorPlayerLayerHostView: NSView {
    private let playerLayer = AVPlayerLayer()
    private let fallbackLayer = CALayer()
    private let ciContext = CIContext()
    private var videoOutput: AVPlayerItemVideoOutput?
    private weak var attachedFallbackItem: AVPlayerItem?
    private var currentItemObservation: NSKeyValueObservation?
    private var videoCompositionObservation: NSKeyValueObservation?
    private var fallbackTimer: Timer?
    private var fallbackImageTask: Task<Void, Never>?
    private var fallbackNeedsRerender = false
    private var fallbackGeneration = 0
    private var fallbackImageTime: CMTime?
    var redrawID = 0

    var player: AVPlayer? {
        get { playerLayer.player }
        set {
            guard playerLayer.player !== newValue else { return }
            currentItemObservation = nil
            playerLayer.player = newValue
            attachFallbackOutput(to: newValue?.currentItem)
            currentItemObservation = newValue?.observe(\.currentItem, options: [.new]) { [weak self] _, change in
                Task { @MainActor in
                    self?.attachFallbackOutput(to: change.newValue ?? nil)
                }
            }
            updateFallbackTimer()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
        fallbackLayer.contentsGravity = .resizeAspect
        fallbackLayer.backgroundColor = NSColor.black.cgColor
        fallbackLayer.isHidden = true
        playerLayer.addSublayer(fallbackLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { false }

    override func makeBackingLayer() -> CALayer {
        playerLayer
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fallbackLayer.frame = bounds
        CATransaction.commit()
    }

    deinit {
        fallbackTimer?.invalidate()
        fallbackImageTask?.cancel()
    }

    private func attachFallbackOutput(to item: AVPlayerItem?) {
        fallbackGeneration += 1
        fallbackImageTask?.cancel()
        fallbackImageTask = nil
        fallbackNeedsRerender = false
        fallbackImageTime = nil
        videoCompositionObservation = nil
        if let videoOutput {
            attachedFallbackItem?.remove(videoOutput)
        }
        attachedFallbackItem = nil
        guard let item else {
            videoOutput = nil
            fallbackLayer.contents = nil
            fallbackLayer.isHidden = true
            updateFallbackTimer()
            return
        }
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        item.add(output)
        videoOutput = output
        attachedFallbackItem = item
        videoCompositionObservation = item.observe(\.videoComposition, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.invalidateFallbackFrame()
            }
        }
        updateFallbackTimer()
        renderFallbackFrame()
    }

    func invalidateFallbackFrame() {
        fallbackGeneration += 1
        fallbackImageTask?.cancel()
        fallbackImageTask = nil
        fallbackNeedsRerender = false
        fallbackImageTime = nil
        renderFallbackFrame()
    }

    private func updateFallbackTimer() {
        fallbackTimer?.invalidate()
        guard playerLayer.player != nil else {
            fallbackTimer = nil
            return
        }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.renderFallbackFrame()
        }
        fallbackTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func renderFallbackFrame() {
        guard let player = playerLayer.player,
              let output = videoOutput else { return }
        let itemTime = player.currentTime()
        guard let pixelBuffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) else {
            renderFallbackStillFrame(from: player.currentItem, at: itemTime)
            return
        }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else { return }
        fallbackLayer.contents = cgImage
        fallbackLayer.isHidden = false
    }

    private func renderFallbackStillFrame(from item: AVPlayerItem?, at time: CMTime) {
        guard let item else { return }
        guard fallbackImageTask == nil else {
            fallbackNeedsRerender = true
            return
        }
        let requestedTime = time.seconds.isFinite && time.seconds >= 0 ? time : .zero
        if let fallbackImageTime,
           fallbackLayer.contents != nil,
           abs(fallbackImageTime.seconds - requestedTime.seconds) < 0.03 {
            return
        }
        fallbackImageTime = requestedTime
        let generation = fallbackGeneration
        let asset = item.asset
        let videoComposition = item.videoComposition
        fallbackImageTask = Task { [weak self] in
            let generator = AVAssetImageGenerator(asset: asset)
            generator.videoComposition = videoComposition
            generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 30)
            generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 30)
            let image = try? await generator.image(at: requestedTime).image
            await MainActor.run {
                guard let self else { return }
                self.fallbackImageTask = nil
                if generation == self.fallbackGeneration, let image {
                    self.fallbackLayer.contents = image
                    self.fallbackLayer.isHidden = false
                }
                if self.fallbackNeedsRerender {
                    self.fallbackNeedsRerender = false
                    self.fallbackImageTime = nil
                    self.renderFallbackFrame()
                }
            }
        }
    }
}

private struct EditorKeyboardShortcutView: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool

    func makeNSView(context: Context) -> ShortcutView {
        let view = ShortcutView()
        view.onKeyDown = onKeyDown
        return view
    }

    func updateNSView(_ nsView: ShortcutView, context: Context) {
        nsView.onKeyDown = onKeyDown
    }

    final class ShortcutView: NSView {
        var onKeyDown: ((NSEvent) -> Bool)?
        private var keyMonitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            installKeyMonitorIfNeeded()
        }

        deinit {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
            }
        }

        private func installKeyMonitorIfNeeded() {
            guard keyMonitor == nil else { return }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.window else {
                    return event
                }
                return self.onKeyDown?(event) == true ? nil : event
            }
        }
    }
}

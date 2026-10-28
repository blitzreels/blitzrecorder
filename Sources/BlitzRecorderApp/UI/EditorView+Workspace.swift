import AppKit
import SwiftUI

extension EditorView {
    var toolbar: some View {
        EditorToolbar(
            vm: vm,
            title: ProjectTitlePresentation(.init(
                title: project?.displayTitle ?? "Last recording",
                known: vm.folderIndex.known
            )),
            onFillWindow: fillWindow,
            onSelectOutputLayout: {
                playback.pauseForEditing()
                vm.selectOutputLayout($0)
            },
            exportButton: AnyView(HStack(spacing: 8) {
                Button { showOutputs(.link) } label: { Label("Share", systemImage: BlitzSymbols.share).lineLimit(1).fixedSize() }
                .blitzButton(.secondary)
                .controlSize(.large)
                .disabled(project == nil)
                .help("Create a watch link anyone can open")
                Button { showOutputs(.file) } label: {
                    Label("Export", systemImage: BlitzSymbols.export).lineLimit(1).fixedSize()
                }
                .blitzButton(inspectorTab == .exports ? .secondary : .accent)
                .controlSize(.large)
                .disabled(project == nil || vm.state != .idle)
                .help("Save a video file to your Mac")
            })
        )
    }

    func sourceResolution(for project: RecordingProject) -> OutputResolution {
        OutputResolution(rawValue: project.settings.outputResolution) ?? .p1080
    }

    func applyEditorState(_ project: RecordingProject) {
        if let restored = EditorExportRecipe.restored(snapshot: project.editorState.exportRecipe) {
            selectedExportPreset = restored.preset
            selectedFormat = restored.format
            selectedResolution = restored.resolution
            selectedExportFramesPerSecond = restored.framesPerSecond
            selectedExportQuality = restored.quality
            selectedExportPlaybackRate = restored.playbackRate
            selectedExportTargetSize = restored.targetFileSize
        } else {
            selectedFormat = project.outputVideoFormat(fallback: vm.settings.outputVideoFormat)
            applyExportPreset(EditorExportPresetRequest(preset: .balanced, project: project))
            selectedExportPlaybackRate = .normal
            selectedExportTargetSize = nil
        }
        backgroundMusicBookmarkData = project.editorState.backgroundMusicBookmarkData
        let resolved = EditorBackgroundMusicResolution.resolve(.init(
            path: project.editorState.backgroundMusicPath,
            bookmarkData: project.editorState.backgroundMusicBookmarkData,
            volume: project.editorState.backgroundMusicVolume
        ))
        if let refreshed = resolved.refreshedBookmarkData {
            backgroundMusicBookmarkData = refreshed
        }
        backgroundMusic = resolved.music
    }

    var editorStateSnapshot: RecordingProject.EditorStateSnapshot {
        RecordingProject.EditorStateSnapshot(
            hiddenVideoSources: playback.hiddenKinds.map(\.rawValue).sorted(),
            mutedAudioSources: playback.mutedSources.map(\.rawValue).sorted(),
            backgroundMusicPath: backgroundMusic?.url.path,
            backgroundMusicBookmarkData: backgroundMusicBookmarkData,
            backgroundMusicVolume: backgroundMusic?.volume,
            exportRecipe: RecordingProject.ExportRecipeSnapshot(
                preset: selectedExportPreset.rawValue,
                format: selectedFormat.rawValue,
                resolution: selectedResolution.rawValue,
                framesPerSecond: selectedExportFramesPerSecond,
                quality: selectedExportQuality.rawValue,
                playbackRate: selectedExportPlaybackRate.value,
                targetFileSize: selectedExportTargetSize
            ),
            audioLevels: playback.audioLevels == .unity ? nil : playback.audioLevels
        )
    }

    func persistEditorState(_ actionName: String) {
        guard vm.applyProjectEditorState(.init(
            editorState: editorStateSnapshot,
            actionName: actionName
        )) else {
            editErrorMessage = vm.detailMessage
            return
        }
    }

    var exportRecipe: EditorExportRecipe {
        exportRecipe(for: .file)
    }

    func exportRecipe(for destination: EditorExportDestination) -> EditorExportRecipe {
        EditorExportRecipe.make(exportRecipeRequest(for: destination))
    }

    func exportSizeEstimate(_ quality: ExportVideoQuality) -> String {
        EditorExportRecipe.estimatedSize(exportRecipeRequest(for: .file), quality: quality)
    }

    private func exportRecipeRequest(for destination: EditorExportDestination) -> EditorExportRecipe.Request {
        let duration = TimelineTimeMap(
            takeDuration: TimelineTimeMap.time(timelineDuration),
            cuts: vm.lastExportedProject?.edits.enabledCuts ?? []
        ).outputDuration.seconds
        return EditorExportRecipe.Request(
            preset: selectedExportPreset,
            sourceResolution: project.map { sourceResolution(for: $0) } ?? vm.settings.outputResolution,
            sourceFramesPerSecond: project?.settings.framesPerSecond ?? vm.settings.framesPerSecond,
            customResolution: selectedResolution,
            customFramesPerSecond: selectedExportFramesPerSecond,
            customVideoQuality: selectedExportQuality,
            layout: captureLayout ?? vm.settings.layout,
            layoutCount: exportLayouts(for: destination).count,
            audioBitrate: vm.settings.audioQuality.bitrate,
            duration: duration,
            playbackRate: selectedExportPlaybackRate.value,
            destination: destination,
            targetFileSize: selectedExportTargetSize
        )
    }

    var selectedExportLayouts: [CaptureLayout] {
        exportLayouts(for: .file)
    }

    func exportLayouts(for destination: EditorExportDestination) -> [CaptureLayout] {
        destination.layouts(.init(
            current: vm.lastExportedProject?.selectedOutputLayout ?? .horizontal,
            additional: additionalExportLayouts))
    }

    var exportPerformanceProfile: ExportPerformanceProfile {
        exportRecipe.profile
    }

    func prepareExport() {
        exportVideo(to: .file)
    }

    var outputsPane: EditorOutputsPane {
        let shareRecipe = exportRecipe(for: .link)
        let recipe = exportDestination == .link ? shareRecipe : exportRecipe
        let layouts = exportLayouts(for: exportDestination)
        let sharing = HostedVideoShareController.shared
        return EditorOutputsPane(
            controller: sharing,
            destination: Binding(get: { exportDestination }, set: showOutputs),
            summary: EditorOutputSummary(
                formats: layouts.count > 1 ? "\(layouts.count) videos"
                    : EditorExportLayouts.title(vm.lastExportedProject?.selectedOutputLayout ?? .horizontal),
                resolution: recipe.profile.resolution,
                framesPerSecond: recipe.profile.framesPerSecond
            ).text,
            exportSettings: exportControls(.controls),
            exportAction: exportControls(.action),
            share: HostedVideoSharePanel(
                controller: sharing,
                context: .project(.init(path: project?.projectPath, estimatedSize: shareRecipe.estimatedSize)),
                preparation: preparesHostedExport ? .init(status: exportStatus, export: { exportVideo(to: .link) }) : nil,
                newExport: { preparesHostedExport = true },
                showLibrary: {
                    vm.projectLibraryNavigation.section = .shared
                    vm.showProjects()
                }
            ),
            history: .init(
                outputs: outputHistory,
                featuredLink: preparesHostedExport ? nil : sharing.sharedURL(forProject: project?.projectPath),
                canShareFile: sharing.canShare && !sharing.isRunning && !vm.isExporting,
                shareFile: shareExportedFile,
                reuseSettings: reuseExportSettings
            )
        )
    }

    private func exportControls(_ section: EditorExportSettings.Section) -> EditorExportControls {
        EditorExportControls(
            vm: vm,
            project: project,
            additionalExportLayouts: $additionalExportLayouts,
            selectedExportPreset: $selectedExportPreset,
            selectedFormat: $selectedFormat,
            selectedResolution: $selectedResolution,
            selectedExportFramesPerSecond: $selectedExportFramesPerSecond,
            selectedExportQuality: $selectedExportQuality,
            selectedExportPlaybackRate: $selectedExportPlaybackRate,
            selectedExportTargetSize: $selectedExportTargetSize,
            recipe: exportRecipe,
            sizeEstimate: exportSizeEstimate,
            persist: persistEditorState,
            export: prepareExport,
            section: section
        )
    }

    var outputHistory: EditorOutputHistory {
        EditorOutputHistory(
            exports: project?.exports ?? [],
            links: project.map { HostedVideoShareController.shared.links(forProject: $0.projectPath) } ?? []
        )
    }

    func showOutputs(_ destination: EditorExportDestination) {
        if destination == .link {
            let sharing = HostedVideoShareController.shared
            preparesHostedExport = !sharing.isRunning && !sharing.belongsToProject(project?.projectPath)
        }
        exportDestination = destination
        inspectorTab = .exports
    }

    func reuseExportSettings(_ record: RecordingProject.ExportRecord) {
        guard let restored = EditorExportRecipe.reused(record) else { return }
        if let layout = record.layout.flatMap(CaptureLayout.init(rawValue:)),
           layout != vm.lastExportedProject?.selectedOutputLayout {
            playback.pauseForEditing()
            vm.selectOutputLayout(layout)
        }
        additionalExportLayouts = []
        selectedExportPreset = .custom
        selectedResolution = restored.resolution
        selectedExportFramesPerSecond = restored.framesPerSecond
        selectedExportQuality = restored.quality
        selectedFormat = restored.format
        selectedExportTargetSize = record.videoBitrate == nil ? nil : record.fileSizeBytes
        selectedExportPlaybackRate = ExportPlaybackRate(clamping: record.playbackRate ?? 1)
        persistEditorState("Reuse Export Settings")
        showOutputs(.file)
    }

    func exportVideo(to destination: EditorExportDestination) {
        guard !vm.exports.isExportingVariants else { return }
        let profile = exportRecipe(for: destination).profile
        let request = EditorExportRequest(
            outputFormat: destination == .link ? .mp4 : profile.videoQuality.resolvedOutputFormat(selectedFormat),
            performanceProfile: profile,
            hiddenVideoSources: playback.hiddenKinds,
            mutedAudioSources: playback.mutedSources,
            backgroundMusic: backgroundMusic,
            playbackRate: selectedExportPlaybackRate.value
        )
        let sharesExport = destination == .link
        let projectPath = project?.projectPath
        shareOutcome = nil
        showsExportResult = true
        vm.exportOutputVariants(.init(export: request, layouts: exportLayouts(for: destination), onCompletion: { urls in
            guard sharesExport, let url = urls.first else { return }
            HostedVideoShareController.shared.select(.init(fileURL: url, projectPath: projectPath))
            HostedVideoShareController.shared.start()
            if vm.lastExportedProject?.projectPath == projectPath {
                preparesHostedExport = false
            }
        }))
    }

    func applyExportPreset(_ request: EditorExportPresetRequest) {
        let applied = EditorExportRecipe.applyingPreset(
            request.preset,
            sourceResolution: sourceResolution(for: request.project),
            sourceFramesPerSecond: request.project.settings.framesPerSecond,
            customResolution: selectedResolution,
            customFramesPerSecond: selectedExportFramesPerSecond,
            customQuality: selectedExportQuality,
            currentFormat: selectedFormat
        )
        selectedExportPreset = applied.preset
        selectedResolution = applied.resolution
        selectedExportFramesPerSecond = applied.framesPerSecond
        selectedExportQuality = applied.quality
        selectedFormat = applied.format
    }

    var exportStatus: EditorExportStatus? {
        if vm.exports.isExportingVariants {
            return .exporting(.init(
                title: "Exporting format \(vm.exports.variantExportIndex) of \(vm.exports.variantExportTotal)",
                percentage: vm.exportProgressLabel,
                detail: nil,
                value: (Double(max(0, vm.exports.variantExportIndex - 1)) + vm.exports.exportProgress) / Double(max(1, vm.exports.variantExportTotal))
            ))
        }
        if vm.isExporting {
            return .exporting(.init(
                title: "Exporting video",
                percentage: vm.exportProgressLabel,
                detail: nil,
                value: vm.exports.exportProgress
            ))
        }
        if let error = vm.exports.lastExportError { return .failed(error) }
        if let url = vm.exports.lastExportSucceededURL { return .succeeded(url) }
        return nil
    }

    var playerColumn: some View {
        EditorCanvasStage(
            playback: playback,
            inspectorTab: inspectorTab,
            privacy: privacy,
            textCanvas: .init(vm: vm, playback: playback, selection: $selection, error: $editErrorMessage),
            sourceCropDraft: sourceCropDraft,
            layoutDraft: layoutDraft,
            canvasAspectRatio: canvasAspectRatio,
            ratioLabel: ratioLabel,
            frameRatioBar: frameRatioBar,
            layers: { displayedCanvasLayers },
            editErrorMessage: $editErrorMessage,
            onSelectLayer: { layer in
                if let id = layer?.assetID {
                    selection = .asset(id)
                } else if layer == nil, case .asset = selection {
                    selection = nil
                }
            },
            onMove: handleLayerMove,
            onResize: handleLayerResize,
            onCropChange: updateEditorSourceCrop,
            onCropDone: applyEditorSourceCrop,
            onCropReset: resetEditorSourceCrop,
            onCropCancel: cancelEditorSourceCrop
        )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(14)
    }
}

extension EditorView {
    var frameRatioBar: EditorFrameRatioBar.Configuration? {
        guard inspectorTab == .layout, sourceCropDraft == nil, let kind = selectedVideoLayerKind,
              let scene = currentEventScene else { return nil }
        return EditorFrameRatioBar.Configuration(
            options: kind.isCamera && EditorSceneTiles.isTiled(scene)
                ? tileShapeOptions(scene: scene)
                : frameRatioOptions(.init(kind: kind, scene: scene)),
            isLocked: aspectRatioLockedKinds.contains(kind),
            toggleLock: {
                if aspectRatioLockedKinds.contains(kind) { aspectRatioLockedKinds.remove(kind) }
                else { aspectRatioLockedKinds.insert(kind) }
            }
        )
    }

    private func frameRatioOptions(_ request: EditorFrameRatioSceneRequest) -> [EditorFrameRatioBar.Option] {
        let sourceRatio = playback.sourceAspectRatios(for: request.scene)[request.kind] ?? 1
        let selected = EditorFrameRatio.selectedPreset(request, canvasAspectRatio: canvasAspectRatio, sourceRatio: sourceRatio)
        return EditorFrameRatio.availablePresets(sourceRatio: sourceRatio).map { preset in
            .init(title: preset.title, help: "Make this layer \(preset.title)", isSelected: preset == selected,
                  select: { applyFrameRatio(.init(kind: request.kind, preset: preset)) })
        }
    }

    /// In a two-camera scene a camera's shape is both tiles' shape, so the tiles stay even.
    private func tileShapeOptions(scene: RecordingScene) -> [EditorFrameRatioBar.Option] {
        let context = EditorSceneTiles.Context(scene: scene, layout: captureLayout ?? .horizontal,
                                               sourceAspectRatios: playback.sourceAspectRatios(for: scene))
        let current = EditorSceneTiles.current(context)
        let cameraRatio = EditorSceneTiles.cameraAspectRatio(context)
        return SceneTileShape.options(cameraAspectRatio: cameraRatio).map { shape in
            .init(title: shape.title(cameraAspectRatio: cameraRatio),
                  help: "Both cameras: " + shape.help(includesScreen: EditorSceneTiles.includesScreen(scene)),
                  isSelected: current?.shape == shape,
                  select: {
                      let spacing = current?.spacing ?? SceneTiles.defaults(for: context.layout).spacing
                      applySceneTiles(.init(tiles: .init(spacing: spacing, shape: shape), context: context))
                  })
        }
    }

    func applySceneTiles(_ change: EditorSceneTiles.Change) {
        playback.pauseForEditing()
        guard vm.applyProjectSceneEdit(eventIndex: currentEventIndex, EditorSceneTiles.edit(change)) else {
            editErrorMessage = vm.detailMessage
            return
        }
    }

    private func applyFrameRatio(_ request: EditorFrameRatioChange) {
        guard let scene = currentEventScene else { return }
        let edited = EditorFrameRatio.applied(
            request,
            scene: scene,
            sourceRatio: playback.sourceAspectRatios(for: scene)[request.kind] ?? 1,
            canvasAspectRatio: canvasAspectRatio
        )
        playback.pauseForEditing()
        guard vm.applyProjectSceneEdit(eventIndex: currentEventIndex, { editedScene in
            editedScene.sceneLayout = edited.sceneLayout
            editedScene.cameraContentMode = edited.cameraContentMode
        }) else {
            editErrorMessage = vm.detailMessage
            return
        }
    }
}

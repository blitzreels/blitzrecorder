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
                Button(action: openSharing) { Label("Share", systemImage: "link").lineLimit(1).fixedSize() }
                .blitzButton(.secondary)
                .controlSize(.large)
                .disabled(project == nil)
                .accessibilityValue(showsHostingShare ? "Open" : "Closed")
                .help("Create a watch link anyone can open")
                EditorExportControls(
                vm: vm,
                project: project,
                isPresented: $isExportPopoverPresented,
                additionalExportLayouts: $additionalExportLayouts,
                selectedExportPreset: $selectedExportPreset,
                selectedFormat: $selectedFormat,
                selectedResolution: $selectedResolution,
                selectedExportFramesPerSecond: $selectedExportFramesPerSecond,
                selectedExportQuality: $selectedExportQuality,
                selectedExportPlaybackRate: $selectedExportPlaybackRate,
                recipe: exportRecipe,
                persist: persistEditorState,
                export: prepareExport
            )
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
        } else {
            selectedFormat = EditorExportRecipe.fallbackFormat(
                projectFormat: project.settings.outputVideoFormat,
                fallbackFormat: vm.settings.outputVideoFormat
            )
            applyExportPreset(EditorExportPresetRequest(preset: .balanced, project: project))
            selectedExportPlaybackRate = .normal
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
                playbackRate: selectedExportPlaybackRate.value
            )
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
        let duration = TimelineTimeMap(
            takeDuration: TimelineTimeMap.time(timelineDuration),
            cuts: vm.lastExportedProject?.edits.enabledCuts ?? []
        ).outputDuration.seconds
        return EditorExportRecipe.make(.init(
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
            destination: destination
        ))
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
        isExportPopoverPresented = false
        showsHostingShare = false
        exportVideo(to: .file)
    }

    func openSharing() {
        let sharing = HostedVideoShareController.shared
        preparesHostedExport = !sharing.isRunning && !sharing.belongsToProject(project?.projectPath)
        showsHostingShare = true
    }

    func exportVideo(to destination: EditorExportDestination) {
        guard !vm.isExportingVariants else { return }
        let profile = exportRecipe(for: destination).profile
        isExportPopoverPresented = false
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
        if vm.isExportingVariants {
            return .exporting(.init(
                title: "Exporting format \(vm.variantExportIndex) of \(vm.variantExportTotal)",
                percentage: vm.exportProgressLabel,
                detail: nil,
                value: (Double(max(0, vm.variantExportIndex - 1)) + vm.exportProgress) / Double(max(1, vm.variantExportTotal))
            ))
        }
        if vm.isExporting {
            return .exporting(.init(
                title: "Exporting video",
                percentage: vm.exportProgressLabel,
                detail: nil,
                value: vm.exportProgress
            ))
        }
        if let error = vm.lastExportError { return .failed(error) }
        if let url = vm.lastExportSucceededURL { return .succeeded(url) }
        return nil
    }

    var playerColumn: some View {
        EditorCanvasStage(
            playback: playback,
            inspectorTab: inspectorTab,
            privacy: privacy,
            cameraCropDraft: cameraCropDraft,
            layoutDraft: layoutDraft,
            canvasAspectRatio: canvasAspectRatio,
            ratioLabel: ratioLabel,
            layers: { displayedCanvasLayers },
            editErrorMessage: $editErrorMessage,
            onSelectLayer: { layer in
                if let id = layer.assetID {
                    selection = .asset(id)
                }
            },
            onMove: handleLayerMove,
            onResize: handleLayerResize,
            onCropChange: updateEditorCameraCrop,
            onCropDone: applyEditorCameraCrop,
            onCropReset: resetEditorCameraCrop,
            onCropCancel: cancelEditorCameraCrop
        )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(14)
    }
}

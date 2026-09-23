import AppKit
import SwiftUI

extension EditorView {
    var toolbar: some View {
        EditorToolbar(
            vm: vm,
            title: project?.displayTitle ?? "Last recording",
            onFillWindow: fillWindow,
            onSelectOutputLayout: {
                playback.pauseForEditing()
                vm.selectOutputLayout($0)
            },
            exportButton: AnyView(EditorExportControls(
                vm: vm,
                project: project,
                isPresented: $isExportPopoverPresented,
                inspectorTab: $inspectorTab,
                exportLayouts: $exportLayouts,
                selectedExportPreset: $selectedExportPreset,
                selectedFormat: $selectedFormat,
                selectedResolution: $selectedResolution,
                selectedExportFramesPerSecond: $selectedExportFramesPerSecond,
                selectedExportQuality: $selectedExportQuality,
                selectedExportPlaybackRate: $selectedExportPlaybackRate,
                backgroundMusic: $backgroundMusic,
                backgroundMusicBookmarkData: $backgroundMusicBookmarkData,
                recipe: exportRecipe,
                persist: persistEditorState,
                applyPreset: applyExportPreset,
                export: exportVideo
            ))
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
            layoutCount: exportLayouts.isEmpty ? 1 : exportLayouts.count,
            audioBitrate: vm.settings.audioQuality.bitrate,
            duration: duration,
            playbackRate: selectedExportPlaybackRate.value
        ))
    }

    var exportPerformanceProfile: ExportPerformanceProfile {
        exportRecipe.profile
    }

    func exportVideo() {
        let profile = exportRecipe.profile
        isExportPopoverPresented = false
        let request = EditorExportRequest(
            outputFormat: profile.videoQuality.resolvedOutputFormat(selectedFormat),
            performanceProfile: profile,
            hiddenVideoSources: playback.hiddenKinds,
            mutedAudioSources: playback.mutedSources,
            backgroundMusic: backgroundMusic,
            playbackRate: selectedExportPlaybackRate.value
        )
        let layouts = exportLayouts.isEmpty ? [vm.lastExportedProject?.selectedOutputLayout ?? .horizontal]
            : CaptureLayout.allCases.filter { exportLayouts.contains($0) }
        vm.exportOutputVariants(.init(export: request, layouts: layouts))
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
                percentage: vm.sessionProgressLabel,
                detail: vm.sessionProgressDetail,
                value: (Double(max(0, vm.variantExportIndex - 1)) + vm.renderProgress) / Double(max(1, vm.variantExportTotal))
            ))
        }
        if vm.state == .finishing {
            return .exporting(.init(
                title: vm.sessionProgressTitle,
                percentage: vm.sessionProgressLabel,
                detail: vm.sessionProgressDetail,
                value: vm.sessionProgressValue
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

import AppKit
import SwiftUI

extension EditorView {
    var currentEventIndex: Int {
        EditorTimelineIndex.eventIndex(at: playback.currentTime, in: sceneEvents)
    }

    var currentEventScene: RecordingScene? {
        sceneEvents.indices.contains(currentEventIndex) ? sceneEvents[currentEventIndex].scene : nil
    }

    func canEditLayout(of scene: RecordingScene) -> Bool {
        EditorCanvasSession.canEditLayout(scene, isPlaybackReady: playback.isReady)
    }

    var displayedCanvasLayers: [EditorCanvasLayer] {
        let frames: [(kind: SceneLayerKind, frame: CGRect)]
        let editable: Bool
        let draftScene = layoutDraft?.scene ?? canvasSceneDraft
        if let draftScene {
            frames = playback.layerFrames(for: draftScene)
            editable = true
        } else {
            frames = playback.layerFrames(at: playback.currentTime)
            editable = currentEventScene.map(canEditLayout(of:)) ?? false
        }
        return EditorCanvasLayers.make(
            frames: frames,
            canvasAspectRatio: canvasAspectRatio,
            lockedKinds: aspectRatioLockedKinds,
            selection: selection,
            isEditable: editable,
            assetID: { asset(for: $0)?.id }
        )
    }

    func ensureLayoutDraft() -> EditorLayoutDraft? {
        guard let result = EditorCanvasSession.ensureDraft(
            existing: layoutDraft,
            eventIndex: currentEventIndex,
            events: sceneEvents,
            currentTime: playback.currentTime,
            duration: timelineDuration,
            isPlaybackReady: playback.isReady
        ) else { return nil }
        if layoutDraft == nil {
            playback.pauseForEditing()
            if let seekTime = result.seekTime {
                playback.seek(to: seekTime)
            }
            layoutDraft = result.draft
        }
        return result.draft
    }

    func handleLayerMove(kind: SceneLayerKind, translation: CGSize, ended: Bool) {
        guard var draft = ensureLayoutDraft() else { return }
        if let asset = asset(for: kind) {
            selection = .asset(asset.id)
        }
        draft.applyMove(kind: kind, translation: translation)
        layoutDraft = draft
        playback.setPreviewSceneOverride(draft.scene, at: playback.currentTime)
        if ended {
            commitLayoutDraft(draft)
        }
    }

    func handleLayerResize(kind: SceneLayerKind, anchor: ResizeAnchor, translation: CGSize, ended: Bool) {
        guard var draft = ensureLayoutDraft() else { return }
        draft.applyResize(
            kind: kind,
            anchor: anchor,
            translation: translation,
            aspectLocked: aspectRatioLockedKinds.contains(kind),
            visibleStartFrame: resizeVisibleStartFrame(kind: kind, draft: draft)
        )
        layoutDraft = draft
        playback.setPreviewSceneOverride(draft.scene, at: playback.currentTime)
        if ended {
            commitLayoutDraft(draft)
        }
    }

    func resizeVisibleStartFrame(kind: SceneLayerKind, draft: EditorLayoutDraft) -> CGRect? {
        guard kind == .camera, draft.scene.cameraContentMode == .fit else { return nil }
        var startScene = draft.scene
        startScene.sceneLayout = draft.startLayout
        return playback.layerFrames(for: startScene).first(where: { $0.kind == kind })?.frame
    }

    func commitLayoutDraft(_ draft: EditorLayoutDraft) {
        func clearPreview() {
            layoutDraft = nil
            playback.setPreviewSceneOverride(nil, at: playback.currentTime)
        }
        guard draft.hasLayoutChanges else {
            clearPreview()
            return
        }
        let before = vm.lastExportedProject
        let succeeded = vm.applyProjectSceneEdit(eventIndex: draft.eventIndex) {
            $0.sceneLayout = draft.scene.sceneLayout
            $0.cameraContentMode = draft.scene.cameraContentMode
        }
        switch EditorCanvasSession.commit(
            hasChanges: true,
            succeeded: succeeded,
            projectChanged: vm.lastExportedProject != before
        ) {
        case .discard, .apply:
            break
        case .failed:
            clearPreview()
            editErrorMessage = "The layout change could not be saved."
        case .revertUnchanged:
            clearPreview()
        }
    }

    func previousBoundary() -> Double {
        EditorTimelineIndex.previousBoundary(at: playback.currentTime, in: segmentBoundaries)
    }

    func nextBoundary() -> Double {
        EditorTimelineIndex.nextBoundary(
            at: playback.currentTime,
            in: segmentBoundaries,
            duration: timelineDuration
        )
    }

    @discardableResult
    func handleKeyboardShortcut(_ event: NSEvent) -> Bool {
        switch EditorKeyboardDispatch.action(
            EditorKeyboardSession.resolve(.init(
                isShowingSettings: vm.isShowingSettings,
                isExportPopoverPresented: isExportPopoverPresented,
                showsTimelineShortcuts: showsTimelineShortcuts,
                isFinishing: vm.state == .finishing,
                isPlaybackReady: playback.isReady,
                keyCode: event.keyCode,
                characters: event.charactersIgnoringModifiers ?? "",
                modifiers: event.modifierFlags
            )),
            zoom: timelineZoom,
            duration: timelineDuration
        ) {
        case .ignore:
            return false
        case .showHelp:
            showsTimelineShortcuts = true
            return true
        case .togglePlayback:
            playback.togglePlayback()
        case .pause:
            playback.pauseForEditing()
        case .playForward:
            playback.playForwardOrIncreaseRate()
        case .seekBy(let seconds):
            playback.seek(by: seconds)
        case .stepFrames(let frames):
            playback.step(byFrames: frames)
        case .goToStart:
            playback.seek(to: 0)
        case .goToEnd:
            playback.seek(to: timelineDuration)
        case .previousBoundary:
            playback.seek(to: previousBoundary())
        case .nextBoundary:
            playback.seek(to: nextBoundary())
        case .split:
            splitTimelineSelection()
        case .deleteSelection:
            return deleteSelection()
        case .restoreSelection:
            restoreSelectedRange()
        case .toggleTrack:
            return toggleSelectedAsset()
        case .markIn:
            markRangeIn()
        case .markOut:
            markRangeOut()
        case .clearSelection:
            if inspectorTab == .privacy { privacy.select(nil) }
            selection = nil
        case .zoom(let zoom):
            timelineZoom = zoom
        }
        return true
    }

    func markRangeIn() {
        guard playback.isReady else { return }
        if let range = EditorTimeRange.markIn(
            time: playback.currentTime,
            existingEnd: selection?.timeRange?.end,
            duration: timelineDuration
        ) {
            selection = .range(range)
        }
    }

    func placedSelection(_ kind: EditorPlacedItem.Kind) -> Binding<UUID?> {
        Binding(get: {
            if case .placed(let id) = selection, id.kind == kind { return id.value }
            return nil
        }, set: { value in
            if let value { selection = .placed(.init(kind: kind, value: value)) }
            else if case .placed(let id) = selection, id.kind == kind { selection = nil }
        })
    }

    func selectPlacedItem(_ id: EditorPlacedItem.ID) {
        if id.kind != .mask, privacy.selectedID != nil { privacy.select(nil) }
        if id.kind == .music { inspectorTab = .audio; return }
        guard let project = vm.editorProject,
              let item = EditorPlacedTrack.resolve(project.edits).flatMap(\.items).first(where: { $0.id == id }) else { return }
        switch id.kind {
        case .music: break
        case .mask:
            inspectorTab = .privacy
            privacy.configure(.init(vm: vm, playback: playback))
            if privacy.selectedID != id.value { privacy.select(id.value) }
        case .text: inspectorTab = .text
        case .zoom: inspectorTab = .zoom
        }
        let projection = EditorTimelineProjection(.init(duration: timelineDuration, cuts: project.edits.cuts))
        playback.pauseForEditing()
        playback.seek(to: item.timing.previewTime(projection))
    }

    func changePlacedItem(_ change: EditorPlacedItemEditing.Change) {
        guard let edits = placedEdits(change.id.kind),
              let updated = EditorPlacedItemEditing.changing(.init(edits: edits, change: change)), updated != edits else { return }
        let projection = EditorTimelineProjection(.init(duration: timelineDuration, cuts: updated.cuts))
        _ = commitTimelineWrite(.init(
            edits: updated,
            actionName: "Change Item Timing",
            seek: change.timing.previewTime(projection),
            usesOutputText: change.id.kind == .text
        ))
    }

    func removePlacedItem(_ id: EditorPlacedItem.ID) {
        if id.kind == .music {
            backgroundMusic = nil
            backgroundMusicBookmarkData = nil
            persistEditorState("Remove Background Music")
            selection = nil
            return
        }
        guard let edits = placedEdits(id.kind) else { return }
        let updated = EditorPlacedItemEditing.removing(.init(edits: edits, id: id))
        guard updated != edits else { return }
        _ = commitTimelineWrite(.init(
            edits: updated,
            actionName: "Remove Timeline Item",
            clearSelection: true,
            usesOutputText: id.kind == .text,
            clearPrivacy: id.kind == .mask
        ))
    }

    func placedEdits(_ kind: EditorPlacedItem.Kind) -> TimelineEdits? {
        kind == .text ? vm.editorProject?.edits : vm.lastExportedProject?.edits
    }

    func splitTimelineSelection() {
        guard case .placed(let id) = selection else { splitAtPlayhead(); return }
        guard let edits = placedEdits(id.kind), let updated = EditorPlacedItemEditing.splitting(.init(
            edits: edits, id: id, time: playback.currentTime
        )) else { return }
        _ = commitTimelineWrite(.init(
            edits: updated,
            actionName: "Split Timeline Item",
            usesOutputText: id.kind == .text
        ))
    }

    func markRangeOut() {
        guard playback.isReady else { return }
        if let range = EditorTimeRange.markOut(
            time: playback.currentTime,
            existingStart: selection?.timeRange?.start,
            duration: timelineDuration
        ) {
            selection = .range(range)
        }
    }

    func cutSelectedRange() {
        guard playback.isReady, let project, let selected = selection?.rangeSelection else { return }
        guard let write = EditorTimelineWrite.cuttingTogether(
            ranges: selected.ranges,
            edits: project.edits,
            takeDuration: timelineDuration
        ) else {
            editErrorMessage = "Select a range containing kept footage and leave at least 0.1 seconds in the recording."
            return
        }
        _ = commitTimelineWrite(write)
    }

    func restoreSelectedRange() {
        guard playback.isReady, let project, let selected = selection?.rangeSelection else { return }
        guard let write = EditorTimelineWrite.restoringTogether(
            ranges: selected.ranges,
            edits: project.edits,
            takeDuration: timelineDuration
        ) else { return }
        _ = commitTimelineWrite(write)
    }

    func extendClip(_ edits: TimelineEdits) {
        guard playback.isReady, let project, edits != project.edits else { return }
        _ = commitTimelineWrite(.init(edits: edits, actionName: "Extend Clip"))
    }

    func splitAtPlayhead() {
        guard playback.isReady, let project else { return }
        let result = EditorTimelineWrite.splittingClip(
            edits: project.edits,
            time: playback.currentTime,
            duration: timelineDuration,
            silenceCuts: silence.cuts
        )
        if let write = result.write {
            _ = commitTimelineWrite(write)
            return
        }
        if let selection = result.selection {
            self.selection = selection
        }
    }

    @discardableResult
    func commitTimelineWrite(_ write: EditorTimelineWrite) -> Bool {
        playback.pauseForEditing()
        let request = EditorTimelineEditsChange(edits: write.edits, actionName: write.actionName)
        let saved = write.usesOutputText ? vm.applyOutputTextEdits(request) : vm.applyTimelineEdits(request)
        if saved {
            if let seek = write.seek { pendingRangeCutSeek = seek }
            if write.clearSelection { selection = nil }
            if let nextSelection = write.nextSelection { selection = nextSelection }
            if write.clearPrivacy { privacy.select(nil) }
        } else {
            editErrorMessage = vm.detailMessage
        }
        return saved
    }

    @discardableResult
    func deleteSelection() -> Bool {
        switch EditorDeleteRouting.action(deleteRoutingRequest) {
        case .removePlaced:
            if case .placed(let id) = selection { removePlacedItem(id) }
        case .removePrivacy:
            privacy.removeSelected()
        case .toggleSilence:
            if let selected = selection?.silenceSelection { silence.toggleRanges(selected.ranges) }
        case .toggleAsset:
            return toggleSelectedAsset()
        case .cutRange:
            cutSelectedRange()
        case .deleteSegment:
            deleteSelectedSegment()
        case nil:
            return false
        }
        return true
    }

    func deleteSelectedSegment() {
        guard playback.isReady, case .segment(let index) = selection,
            let range = EditorTimeRange.segment(.init(
                eventTimes: sceneEvents.map(\.time), index: index, duration: timelineDuration
            ))
        else { return }
        playback.pauseForEditing()
        if vm.deleteProjectSegment(.init(index: index, duration: timelineDuration)) {
            pendingRangeCutSeek = range.start
            selection = nil
        } else {
            editErrorMessage = vm.detailMessage
        }
    }

    func joinSelectedSegment() {
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
    func toggleSelectedAsset() -> Bool {
        guard case .asset(let id) = selection,
              let asset = assets.first(where: { $0.id == id }),
              assetTracks.toggleableIDs.contains(asset.id) else {
            return false
        }
        toggleTrack(asset)
        return true
    }


    var recordedVideoSources: Set<CaptureSource> {
        Set(playback.hideableKinds.map { $0 == .screen ? CaptureSource.screen : .camera })
    }

    var scenePresetPreview: BlitzScenePreview {
        BlitzScenePreview(
            screen: asset(for: .screen).flatMap { library.filmstrips[$0.id]?.first },
            camera: asset(for: .camera).flatMap { library.filmstrips[$0.id]?.first },
            background: (canvasSceneDraft ?? currentEventScene)?.canvasBackgroundStyle ?? .black
        )
    }

    func updateEditorCameraCrop(_ change: EditorCameraCropInteractionChange) {
        guard let draft = cameraCropDraft,
              let sourceAspectRatio = playback.sourceAspectRatios[.camera] else {
            return
        }
        cameraCropDraft = EditorCameraCropSession.applying(
            change,
            to: draft,
            renderSize: playback.renderSize,
            sourceAspectRatio: sourceAspectRatio
        )
    }

    func applyEditorCameraCrop() {
        guard let draft = cameraCropDraft else { return }
        let commit = EditorCameraCropSession.commit(draft)
        let succeeded = vm.applyProjectSceneEdit(eventIndex: commit.eventIndex) { scene in
            scene.cameraCropAmount = commit.amount
            scene.cameraCropPosition = commit.position
        }
        cameraCropDraft = nil
        if !succeeded {
            editErrorMessage = vm.detailMessage
        }
    }

    func resetEditorCameraCrop() {
        if let cameraCropDraft {
            self.cameraCropDraft = EditorCameraCropSession.resetting(cameraCropDraft)
            return
        }
        playback.pauseForEditing()
        let index = currentEventIndex
        cameraZoomDraft = 0
        let succeeded = vm.applyProjectSceneEdit(eventIndex: index) { scene in
            scene.cameraCropAmount = .zero
            scene.cameraCropPosition = .zero
        }
        cameraZoomDraft = nil
        if !succeeded {
            playback.setPreviewSceneOverride(nil, at: playback.currentTime)
            editErrorMessage = vm.detailMessage
        }
    }

    func cancelEditorCameraCrop() {
        cameraCropDraft = nil
    }

    var canDeleteSelectedSegment: Bool {
        guard let project, case .segment(let index) = selection,
            let range = EditorTimeRange.segment(.init(
                eventTimes: sceneEvents.map(\.time), index: index, duration: timelineDuration
            ))
        else { return false }
        return EditorTimeRange.removing(.init(
            range: range, edits: project.edits, takeDuration: timelineDuration
        )) != nil
    }

    func openSilenceInspector() {
        inspectorTab = .silence
    }



    var divider: some View {
        Rectangle()
            .fill(BlitzUI.separator)
            .frame(height: 1)
    }


}

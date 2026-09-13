import Foundation
import Observation

@MainActor
@Observable
final class PrivacyEditingSession {
    var selectedID: UUID?
    private(set) var draft: PrivacyMask?
    private(set) var isDrawing = false
    var error: String?
    private var configurationRevision = 0
    @ObservationIgnored private weak var vm: RecorderViewModel?
    @ObservationIgnored private weak var playback: EditorPlaybackController?

    struct Configuration {
        let vm: RecorderViewModel
        let playback: EditorPlaybackController
    }

    func configure(_ request: Configuration) {
        vm = request.vm
        playback = request.playback
        configurationRevision &+= 1
    }

    var masks: [PrivacyMask] {
        _ = configurationRevision
        return vm?.lastExportedProject?.edits.privacyMasks ?? []
    }
    var selected: PrivacyMask? { draft ?? masks.first { $0.id == selectedID } }
    var displayedMasks: [PrivacyMask] {
        guard let draft else { return masks }
        return masks.filter { $0.id != draft.id } + [draft]
    }

    func add() {
        guard let playback, !playback.hideableKinds.isEmpty else { return }
        cancelGesture()
        playback.pauseForEditing()
        if playback.currentTime >= playback.duration - 0.05 { playback.seek(to: 0) }
        let mask = PrivacyMask(id: UUID(), source: playback.hideableKinds.contains(.screen) ? .screen : .camera,
            frame: .zero, start: 0, end: playback.duration, style: .cover)
        selectedID = mask.id
        draft = mask
        isDrawing = true
        error = nil
    }

    func select(_ id: UUID?) {
        cancelGesture()
        selectedID = id
        playback?.pauseForEditing()
        if let selected, let playback, !selected.isVisible(at: playback.currentTime) {
            playback.seek(to: min(playback.duration, selected.start + 0.01))
        }
    }

    func preview(_ mask: PrivacyMask) {
        draft = mask
        selectedID = mask.id
        playback?.pauseForEditing()
        playback?.setPrivacyMaskPreview(mask)
    }

    func commit(_ mask: PrivacyMask) {
        guard mask.frame.width >= 0.005, mask.frame.height >= 0.005, mask.end > mask.start,
              var edits = vm?.lastExportedProject?.edits else { cancelGesture(); return }
        if let index = edits.privacyMasks.firstIndex(where: { $0.id == mask.id }) {
            edits.privacyMasks[index] = mask
        } else { edits.privacyMasks.append(mask) }
        guard vm?.applyTimelineEdits(.init(edits: edits, actionName: "Edit Privacy Mask")) == true else {
            error = vm?.detailMessage
            return
        }
        playback?.finishPrivacyMaskPreview(edits.privacyMasks)
        draft = nil
        isDrawing = false
        selectedID = mask.id
        error = nil
    }

    func update(_ mask: PrivacyMask) {
        if isDrawing { draft = mask; playback?.setPrivacyMaskPreview(mask) }
        else { commit(mask) }
    }

    func removeSelected() {
        guard let id = selectedID, var edits = vm?.lastExportedProject?.edits else { return }
        if isDrawing { cancelGesture(); return }
        edits.privacyMasks.removeAll { $0.id == id }
        if vm?.applyTimelineEdits(.init(edits: edits, actionName: "Remove Privacy Mask")) == true {
            playback?.finishPrivacyMaskPreview(edits.privacyMasks)
            draft = nil
            selectedID = nil
            error = nil
        } else { error = vm?.detailMessage }
    }

    func cancelGesture() {
        if isDrawing { selectedID = nil }
        draft = nil
        isDrawing = false
        playback?.setPrivacyMaskPreview(nil)
    }
}

import Foundation
import Observation

@MainActor
@Observable
final class PrivacyEditingSession {
    var selectedID: UUID?
    private(set) var draft: PrivacyMask?
    private(set) var isDrawing = false
    var error: String?
    enum ScanState: Equatable {
        case idle
        case scanning(Double)
        case finished
    }
    private(set) var scanState = ScanState.idle
    private(set) var findings: [PrivacyFinding] = []
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var scannedProjectID: UUID?
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
        if scannedProjectID != request.vm.lastExportedProject?.id { resetScan() }
        PrivacyScanner.warmUp()
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

    func add(style: PrivacyMask.Style) {
        guard let playback, !playback.hideableKinds.isEmpty else { return }
        cancelGesture()
        playback.pauseForEditing()
        if playback.currentTime >= playback.duration - 0.05 { playback.seek(to: 0) }
        let mask = PrivacyMask(id: UUID(), source: playback.hideableKinds.contains(.screen) ? .screen : .camera,
            frame: .zero, start: 0, end: playback.duration, style: style)
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
        guard let id = selectedID else { return }
        if isDrawing { cancelGesture(); return }
        remove(id)
    }

    func remove(_ id: UUID) {
        guard var edits = vm?.lastExportedProject?.edits else { return }
        if isDrawing { cancelGesture() }
        edits.privacyMasks.removeAll { $0.id == id }
        if vm?.applyTimelineEdits(.init(edits: edits, actionName: "Remove Privacy Mask")) == true {
            playback?.finishPrivacyMaskPreview(edits.privacyMasks)
            draft = nil
            if selectedID == id { selectedID = nil }
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

extension PrivacyEditingSession {
    var visibleFindings: [PrivacyFinding] {
        guard let playback else { return [] }
        return findings.filter { playback.currentTime >= $0.start && playback.currentTime < $0.end }
    }

    func scan() {
        guard let project = vm?.lastExportedProject, let playback else { return }
        guard let screen = project.sources.first(where: { $0.role == "screen" && $0.exists }) else {
            error = "This take has no screen video to scan."
            return
        }
        scanTask?.cancel()
        scannedProjectID = project.id
        findings = []
        error = nil
        scanState = .scanning(0)
        let request = PrivacyScanner.Request(
            videoURL: URL(fileURLWithPath: screen.path),
            sourceOffset: project.timelineTrimOffsetSeconds,
            duration: playback.duration,
            onProgress: { [weak self] value in Task { @MainActor in self?.setScanProgress(value) } }
        )
        let signalsURL = URL(fileURLWithPath: project.takeDirectoryPath)
            .appendingPathComponent(RecordingPrivacySignalTrack.fileName)
        let trimOffset = project.timelineTrimOffsetSeconds
        scanTask = Task { [weak self] in
            do {
                let found = try await Task.detached(priority: .userInitiated) {
                    let windows = (try? Data(contentsOf: signalsURL))
                        .flatMap { try? JSONDecoder().decode(RecordingPrivacySignalTrack.self, from: $0) }
                        .map { PrivacyScanner.findings(.init(track: $0, trimOffset: trimOffset, duration: request.duration)) } ?? []
                    return windows + (try await PrivacyScanner.scan(request))
                }.value
                guard let self, !Task.isCancelled else { return }
                self.findings = found.filter { finding in !self.masks.contains { self.covers($0, finding) } }
                    .sorted { $0.start < $1.start }
                self.scanState = .finished
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.scanState = .idle
                self.error = "The scan stopped. Try again."
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        scanState = findings.isEmpty ? .idle : .finished
    }

    func hide(_ ids: Set<UUID>) {
        guard var edits = vm?.lastExportedProject?.edits else { return }
        let chosen = findings.filter { ids.contains($0.id) }
        guard !chosen.isEmpty else { return }
        cancelGesture()
        edits.privacyMasks += chosen.map {
            PrivacyMask(id: UUID(), source: .screen, frame: $0.frame, start: $0.start, end: $0.end, style: .cover)
        }
        guard vm?.applyTimelineEdits(.init(edits: edits, actionName: chosen.count == 1 ? "Hide Private Info" : "Hide All Private Info")) == true else {
            error = vm?.detailMessage
            return
        }
        playback?.finishPrivacyMaskPreview(edits.privacyMasks)
        findings.removeAll { ids.contains($0.id) }
        error = nil
    }

    func ignore(_ id: UUID) {
        findings.removeAll { $0.id == id }
    }

    func reveal(_ finding: PrivacyFinding) {
        cancelGesture()
        selectedID = nil
        playback?.pauseForEditing()
        playback?.seek(to: min(finding.end, finding.start + 0.05))
    }

    private func setScanProgress(_ value: Double) {
        guard case .scanning = scanState else { return }
        scanState = .scanning(min(1, value))
    }

    private func resetScan() {
        scanTask?.cancel()
        scanTask = nil
        findings = []
        scanState = .idle
        scannedProjectID = nil
    }

    private func covers(_ mask: PrivacyMask, _ finding: PrivacyFinding) -> Bool {
        mask.source == .screen && mask.start <= finding.start + 0.05 && mask.end >= finding.end - 0.05
            && PrivacyScanner.overlap(mask.frame, finding.frame) > 0.9
            && mask.frame.width * mask.frame.height >= finding.frame.width * finding.frame.height * 0.9
    }
}

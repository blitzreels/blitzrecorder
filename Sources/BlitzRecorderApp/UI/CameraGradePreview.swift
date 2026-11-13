import AVFoundation
import CoreImage

@MainActor
final class CameraGradePreview {
    struct PopoutTimeline: Equatable {
        let segments: [FinalExportRenderSegment]
        let renderSize: CGSize
        let isCropping: Bool
    }

    private struct PopoutSegment: Equatable {
        let range: CMTimeRange
        let style: CameraPopoutStyle
    }

    struct PlayerEntry {
        let role: String
        let player: AVPlayer
    }

    struct AttachRequest {
        let players: [PlayerEntry]
        let grades: [String: CameraColorGrade]
    }

    private final class GradeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = CameraColorGrade.neutral
        private var storedPopouts: [PopoutSegment] = []

        var popouts: [PopoutSegment] {
            get {
                lock.lock()
                defer { lock.unlock() }
                return storedPopouts
            }
            set {
                lock.lock()
                storedPopouts = newValue
                lock.unlock()
            }
        }

        var needsComposition: Bool { !grade.isNeutral || !popouts.isEmpty }

        var grade: CameraColorGrade {
            get {
                lock.lock()
                defer { lock.unlock() }
                return stored
            }
            set {
                lock.lock()
                stored = newValue
                lock.unlock()
            }
        }
    }

    private final class Entry {
        let role: String
        let player: AVPlayer
        let box = GradeBox()
        var installTask: Task<Void, Never>?
        var isRedrawing = false
        var needsAnotherRedraw = false
        var redrawsForward = false

        init(_ source: PlayerEntry) {
            role = source.role
            player = source.player
        }
    }

    private var entries: [Entry] = []
    private var popoutTimeline: PopoutTimeline?
    private var isGrading = false

    func setGrading(_ grading: Bool) {
        guard isGrading != grading else { return }
        isGrading = grading
        entries.forEach(refresh)
    }

    func attach(_ request: AttachRequest) {
        entries.forEach { $0.installTask?.cancel() }
        entries = request.players.map(Entry.init)
        popoutTimeline = nil
        update(request.grades)
        entries.forEach(refresh)
    }

    func update(_ grades: [String: CameraColorGrade]) {
        for entry in entries {
            let grade = grades[entry.role] ?? .neutral
            guard grade != entry.box.grade else { continue }
            entry.box.grade = grade
            refresh(entry)
        }
    }

    func updatePopouts(_ timeline: PopoutTimeline) {
        guard popoutTimeline != timeline else { return }
        popoutTimeline = timeline
        for entry in entries {
            let segments: [PopoutSegment] = timeline.isCropping ? [] : timeline.segments.compactMap { segment in
                let scene = segment.scene
                guard scene.sceneLayout.cameraMask == .popout,
                      scene.cameraFeeds.camera == entry.role,
                      segment.activeLayerOrder.contains(.camera) else { return nil }
                let geometry = SceneRenderGeometry(canvas: CGRect(origin: .zero, size: timeline.renderSize),
                                                   scene: scene, origin: .lowerLeft)
                guard let placement = geometry.activePlacements.first(where: { $0.kind == .camera }) else { return nil }
                return PopoutSegment(range: segment.timeRange, style: CameraPopoutStyle(.init(
                    placement: placement, headroom: scene.sceneLayout.cameraPopoutHeadroom
                )))
            }
            guard segments != entry.box.popouts else { continue }
            entry.box.popouts = segments
            refresh(entry)
        }
    }

    private func refresh(_ entry: Entry) {
        guard let item = entry.player.currentItem else { return }
        if !needsComposition(entry) {
            entry.installTask?.cancel()
            entry.installTask = nil
            guard item.videoComposition != nil else { return }
            item.videoComposition = nil
            redraw(entry)
        } else if item.videoComposition == nil {
            install(.init(entry: entry, item: item))
        } else {
            redraw(entry)
        }
    }

    private func needsComposition(_ entry: Entry) -> Bool {
        isGrading || entry.box.needsComposition
    }

    private struct InstallRequest {
        let entry: Entry
        let item: AVPlayerItem
    }

    private func install(_ request: InstallRequest) {
        let entry = request.entry
        let item = request.item
        guard entry.installTask == nil else { return }
        let box = entry.box
        let popoutRenderer = CameraPopoutRenderer(quality: .playback)
        let asset = item.asset
        entry.installTask = Task { [weak self, weak entry, weak item] in
            let composition = try? await AVVideoComposition.videoComposition(
                with: asset,
                applyingCIFiltersWithHandler: { request in
                    let grade = box.grade
                    let source = request.sourceImage
                    var image = grade.applied(to: grade.cameraInput(from: source))
                    if let segment = box.popouts.first(where: {
                        CMTimeRangeContainsTime($0.range, time: request.compositionTime)
                    }) {
                        image = popoutRenderer.image(.init(image: image, style: segment.style))
                    }
                    request.finish(with: image, context: nil)
                }
            )
            guard !Task.isCancelled, let entry, let item, let composition else { return }
            entry.installTask = nil
            guard let self, self.needsComposition(entry) else { return }
            item.videoComposition = composition
            self.redraw(entry)
        }
    }

    func redrawLoadedFrames() {
        entries.forEach(redraw)
    }

    private func redraw(_ entry: Entry) {
        guard entry.player.rate == 0 else { return }
        guard !entry.isRedrawing else {
            entry.needsAnotherRedraw = true
            return
        }
        entry.isRedrawing = true
        entry.redrawsForward.toggle()
        let nudge = CMTime(value: entry.redrawsForward ? 1 : -1, timescale: 6_000)
        let target = CMTimeMaximum(.zero, CMTimeAdd(entry.player.currentTime(), nudge))
        entry.player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak entry] _ in
            Task { @MainActor in
                guard let self, let entry else { return }
                entry.isRedrawing = false
                guard entry.needsAnotherRedraw else { return }
                entry.needsAnotherRedraw = false
                self.redraw(entry)
            }
        }
    }
}

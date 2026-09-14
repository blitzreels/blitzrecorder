import Observation
import SwiftUI

@MainActor
@Observable
final class SilenceEditingSession {
    struct Request {
        let vm: RecorderViewModel
        let playback: EditorPlaybackController
        let project: RecordingProject
    }
    var intensity = 1.0
    var threshold = -42.0
    var automaticThreshold = true
    var minimumDuration = 0.5
    var paddingBefore = 0.3
    var paddingAfter = 0.3
    var linkedPadding = true
    var minimumAudio = 0.0
    var customized = false
    private var previousIntensity = 1.0
    private(set) var skipSilence = false
    private(set) var cuts: [TimelineCut] = []
    private var baseCuts: [TimelineCut] = []
    private var transcript: RecordingTranscript?
    private var transcriptCuts: [TimelineCut] = []
    private(set) var nonDialogueRanges: [EditorTimeRange] = []
    private(set) var windows: [SilenceWindow] = []
    private(set) var loading = false
    private(set) var preparingPreview = false
    private(set) var calculating = false
    private(set) var metrics = SilenceTimelineMetrics(.init(duration: 0, proposed: [], saved: []))
    private(set) var error: String?
    private(set) var duration = 0.0
    private(set) var sourceName = "Audio"
    private(set) var audioSourcePaths: Set<String> = []
    @ObservationIgnored private var request: Request?
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var calculationTask: Task<Void, Never>?
    @ObservationIgnored private var sourceURL: URL?
    @ObservationIgnored private var sourceOffset = 0.0
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var active = false

    var removedDuration: Double { timeMap.removedDuration }
    var timeMap: TimelineTimeMap { .init(takeDuration: TimelineTimeMap.time(duration), cuts: cuts.filter(\.isEnabled)) }
    var cutCount: Int { cuts.filter(\.isEnabled).count }
    var suggestsPauses: Bool { intensity > 0 }
    var canClassify: Bool { active && !loading && !calculating && !windows.isEmpty }
    var canApply: Bool {
        !loading && !calculating && !preparingPreview && error == nil && !windows.isEmpty && metrics.hasChanges
            && metrics.outputDuration >= 0.1
    }

    var hasRemovedSilence: Bool {
        request?.vm.lastExportedProject?.edits.enabledCuts.contains { $0.kind == .silence } ?? false
    }

    func prepare(_ request: Request) {
        guard request.playback.duration > 0 else { return }
        if let previous = self.request, active,
            previous.project.projectPath == request.project.projectPath,
            previous.project.timelineTrimOffsetSeconds == request.project.timelineTrimOffsetSeconds,
            duration == request.playback.duration
        {
            self.request = request
            if previous.project.edits.cuts != request.project.edits.cuts
                || previous.project.edits.silenceOverrides != request.project.edits.silenceOverrides {
                baseCuts = request.project.edits.cuts
                updateMetrics()
                if !usesSavedSilenceCuts { recalculate() }
            } else if skipSilence {
                updatePreview()
            }
            return
        }
        cancel()
        self.request = request
        active = true
        duration = request.playback.duration
        baseCuts = request.project.edits.cuts
        windows = []
        transcriptCuts = []
        nonDialogueRanges = []
        error = nil
        skipSilence = false
        updateMetrics()
        let audioSources = request.project.sources.filter {
            ["microphone", "systemAudio"].contains($0.role) && $0.exists
        }
        audioSourcePaths = Set(audioSources.map(\.path))
        let fallback = request.project.sources.first { ["screen", "camera"].contains($0.role) && $0.exists }
        let sources = audioSources.isEmpty ? fallback.map { [$0] } ?? [] : audioSources
        guard let source = sources.first else {
            error = SilenceDetectionError.noAudio.localizedDescription
            return
        }
        sourceURL = URL(fileURLWithPath: source.path)
        sourceOffset = request.project.sourceOffset(forRole: source.role) - request.project.timelineTrimOffsetSeconds
        sourceName =
            sources.count > 1
            ? "Mic + Mac audio"
            : source.role == "microphone"
                ? "Microphone" : source.role == "systemAudio" ? "Mac audio" : "Recording audio"
        loading = true
        let configs = sources.map { source in
            SilenceDetectionRequest(
                audioURL: URL(fileURLWithPath: source.path), takeDuration: duration,
                sourceOffset: request.project.sourceOffset(forRole: source.role)
                    - request.project.timelineTrimOffsetSeconds,
                minimumSilence: minimumDuration, thresholdDB: threshold, previousCuts: cuts)
        }
        let currentGeneration = generation
        analysisTask = Task {
            do {
                let task = Task.detached(priority: .utility) {
                    var tracks: [[SilenceWindow]] = []
                    for config in configs { tracks.append(try await SilenceDetection.windows(config)) }
                    return SilenceDetection.combinedWindows(tracks)
                }
                let result = try await withTaskCancellationHandler(
                    operation: { try await task.value }, onCancel: { task.cancel() })
                guard !Task.isCancelled, currentGeneration == generation else { return }
                windows = result
                loading = false
                if automaticThreshold { threshold = SilenceDetection.suggestedThreshold(result) }
                refreshTranscriptCuts()
                if usesSavedSilenceCuts { updateMetrics() }
                else { recalculate() }
            } catch {
                guard !Task.isCancelled, currentGeneration == generation else { return }
                loading = false
                self.error = error.localizedDescription
            }
        }
    }

    func cancel() {
        active = false
        generation += 1
        analysisTask?.cancel()
        previewTask?.cancel()
        calculationTask?.cancel()
        calculating = false
        loading = false
        preparingPreview = false
    }

    func setPreviewEnabled(_ enabled: Bool) {
        guard skipSilence != enabled else { return }
        skipSilence = enabled
        updatePreview()
    }

    func endPreview() {
        setPreviewEnabled(false)
    }

    func apply() -> Bool {
        guard canApply, let request else { return false }
        var edits = request.vm.lastExportedProject?.edits ?? request.project.edits
        edits.cuts = cuts
        edits.silenceRemovalApplied = true
        previewTask?.cancel()
        request.playback.pauseForEditing()
        guard request.vm.applyTimelineEdits(.init(edits: edits, actionName: "Remove Silence")) else {
            error = request.vm.detailMessage
            return false
        }
        preparingPreview = false
        skipSilence = false
        baseCuts = edits.cuts
        updateMetrics()
        return true
    }

    func restoreSilence() {
        guard let request, var edits = request.vm.lastExportedProject?.edits else { return }
        previewTask?.cancel()
        preparingPreview = false
        skipSilence = false
        request.playback.pauseForEditing()
        edits.cuts.removeAll { $0.kind == .silence }
        edits.silenceRemovalApplied = false
        if request.vm.applyTimelineEdits(.init(edits: edits, actionName: "Restore Silence")) {
            baseCuts = edits.cuts
        } else {
            error = request.vm.detailMessage
        }
        updateMetrics()
    }

    func changeIntensity() {
        customized = false
        switch Int(intensity.rounded()) {
        case 0: break
        case 1:
            minimumDuration = 0.5
            paddingBefore = 0.3
            paddingAfter = 0.3
            minimumAudio = 0
        case 2:
            minimumDuration = 0.3
            paddingBefore = 0.15
            paddingAfter = 0.15
            minimumAudio = 0
        default:
            minimumDuration = 0.15
            paddingBefore = 0.05
            paddingAfter = 0.05
            minimumAudio = 0
        }
        recalculate()
    }

    func setSuggestionsEnabled(_ enabled: Bool) {
        guard enabled != suggestsPauses else { return }
        if enabled {
            intensity = previousIntensity
        } else {
            previousIntensity = intensity
            intensity = 0
        }
        recalculate()
    }

    func selectPacing(_ pacing: SilencePacing) {
        intensity = Double(pacing.rawValue)
        changeIntensity()
    }

    func changeThresholdMode() {
        if automaticThreshold { threshold = SilenceDetection.suggestedThreshold(windows) }
        recalculate()
    }

    private func configuration() -> SilenceDetectionRequest {
        .init(
            audioURL: sourceURL ?? URL(fileURLWithPath: "/"), takeDuration: duration, sourceOffset: sourceOffset,
            minimumSilence: minimumDuration, thresholdDB: threshold, previousCuts: cuts,
            paddingBefore: paddingBefore, paddingAfter: paddingAfter, minimumAudio: minimumAudio,
            overrides: request?.vm.lastExportedProject?.edits.silenceOverrides ?? [])
    }

    func recalculate() {
        guard active, !loading, !windows.isEmpty else { return }
        calculationTask?.cancel()
        error = nil
        calculating = true
        refreshTranscriptCuts()
        let windows = windows
        let configuration = configuration()
        let noCuts = !suggestsPauses
        calculationTask = Task {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            let task = Task.detached(priority: .userInitiated) {
                noCuts
                    ? SilenceDetection.applyingOverrides(.init(
                        cuts: configuration.previousCuts.filter { $0.source == .user },
                        overrides: configuration.overrides
                    ))
                    : SilenceDetection.cuts(.init(windows: windows, configuration: configuration))
            }
            let result = await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
            guard !Task.isCancelled else { return }
            baseCuts = result
            calculating = false
            updateMetrics()
            if skipSilence { updatePreview() }
        }
    }

    func keep(_ range: EditorTimeRange) {
        classify(.init(range: range, classification: .sound))
    }

    func classification(_ range: EditorTimeRange) -> SilenceClassification {
        SilenceTimelineBands.classification(.init(range: range, cuts: cuts))
    }

    func toggle(_ range: EditorTimeRange) {
        classify(.init(range: range, classification: classification(range) == .silence ? .sound : .silence))
    }

    struct ClassificationRequest {
        let range: EditorTimeRange
        let classification: SilenceClassification
    }

    func classify(_ change: ClassificationRequest) {
        classifyTogether([change])
    }

    func toggleRanges(_ ranges: [EditorTimeRange]) {
        classifyTogether(ranges.map {
            .init(range: $0, classification: classification($0) == .silence ? .sound : .silence)
        })
    }

    func classifyTogether(_ changes: [ClassificationRequest]) {
        guard canClassify, !changes.isEmpty, let request, let project = request.vm.lastExportedProject else { return }
        var edits = project.edits
        for change in changes {
            guard let updated = SilenceDetection.classifying(.init(
                range: change.range, classification: change.classification, edits: edits, duration: duration
            )) else {
                error = "Keep at least 0.1 seconds of the recording. This marking was not saved."
                return
            }
            edits = updated
        }
        let actionName = changes.allSatisfy { $0.classification == .sound } ? "Mark as Sound"
            : changes.allSatisfy { $0.classification == .silence } ? "Mark as Silence" : "Switch Sound and Silence"
        request.playback.pauseForEditing()
        guard request.vm.applyTimelineEdits(.init(edits: edits, actionName: actionName)) else {
            error = request.vm.detailMessage
            return
        }
        calculationTask?.cancel()
        calculating = false
        error = nil
        baseCuts = edits.silenceRemovalApplied ? edits.cuts
            : SilenceDetection.applyingOverrides(.init(cuts: baseCuts, overrides: edits.silenceOverrides))
        if let updatedProject = request.vm.lastExportedProject {
            self.request = .init(vm: request.vm, playback: request.playback, project: updatedProject)
        }
        updateMetrics()
        if skipSilence { updatePreview() }
    }

    private var usesSavedSilenceCuts: Bool {
        guard let edits = request?.vm.lastExportedProject?.edits else { return false }
        return edits.silenceRemovalApplied || edits.enabledCuts.contains { $0.kind == .silence }
    }

    func setTranscript(_ transcript: RecordingTranscript?) {
        guard self.transcript != transcript else { return }
        self.transcript = transcript
        refreshTranscriptCuts()
        updateMetrics()
    }

    private func refreshTranscriptCuts() {
        transcriptCuts = transcript.map {
            EditorTranscriptTimeline.items(.init(transcript: $0, windows: windows, threshold: threshold, duration: duration))
                .filter { $0.kind == .nonDialogue }
                .map { .init(start: $0.range.start, end: $0.range.end, kind: .silence, source: .automatic) }
        } ?? []
    }

    var canRemoveNonDialogue: Bool {
        canClassify && !nonDialogueRanges.isEmpty
    }

    func removeNonDialogue() {
        guard canRemoveNonDialogue, let request, let project = request.vm.lastExportedProject else { return }
        guard let edits = EditorTimeRange.removingTogether(.init(
            ranges: nonDialogueRanges, kind: .silence, edits: project.edits, takeDuration: duration)) else {
            error = "Keep at least 0.1 seconds of the recording."
            return
        }
        request.playback.pauseForEditing()
        if request.vm.applyTimelineEdits(.init(edits: edits, actionName: "Remove Silence Without Dialogue")) {
            baseCuts = edits.cuts
            updateMetrics()
        } else {
            error = request.vm.detailMessage
        }
    }

    private func updateMetrics() {
        let saved = request?.vm.lastExportedProject?.edits ?? .empty
        let suggestions = SilenceDetection.applyingOverrides(.init(
            cuts: transcriptCuts, overrides: saved.silenceOverrides)).filter { $0.source == .automatic && $0.isEnabled }
        let projection = EditorTimelineProjection(.init(duration: duration, cuts: saved.cuts))
        let remaining = EditorTranscriptTimeline.remainingSilence(.init(cuts: suggestions, projection: projection))
        nonDialogueRanges = remaining.map { .init(start: $0.start, end: $0.end) }
        cuts = baseCuts + (suggestsPauses ? remaining : [])
        metrics = SilenceTimelineMetrics(
            .init(
                duration: duration, proposed: cuts,
                saved: request?.vm.lastExportedProject?.edits.cuts ?? []
            ))
    }

    func updatePreview() {
        guard active, let request, !loading else { return }
        previewTask?.cancel()
        guard let project = request.vm.lastExportedProject, project.id == request.project.id else { return }
        let proposed = skipSilence ? cuts.filter(\.isEnabled) : project.edits.enabledCuts
        guard
            TimelineTimeMap(takeDuration: TimelineTimeMap.time(duration), cuts: proposed).outputDuration.seconds >= 0.1
        else {
            error = "These settings remove the whole recording. Lower the threshold or keep a segment."
            return
        }
        preparingPreview = true
        previewTask = Task {
            guard !Task.isCancelled else { return }
            await request.playback.load(
                .init(project: project, baseSettings: request.vm.settings, previewCuts: skipSilence ? proposed : nil))
            guard !Task.isCancelled else { return }
            preparingPreview = false
            if let loadError = request.playback.loadError { error = loadError }
        }
    }

}

enum SilenceTime {
    static func label(_ seconds: Double) -> String {
        let time = max(0, seconds.isFinite ? seconds : 0)
        return String(format: "%d:%04.1f", Int(time) / 60, time.truncatingRemainder(dividingBy: 60))
    }
}

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
    private(set) var skipSilence = false
    private(set) var cuts: [TimelineCut] = []
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
            if previous.project.edits.cuts != request.project.edits.cuts {
                cuts = request.project.edits.cuts
                updateMetrics()
                recalculate()
            } else if skipSilence {
                updatePreview()
            }
            return
        }
        cancel()
        self.request = request
        active = true
        duration = request.playback.duration
        cuts = request.project.edits.cuts
        windows = []
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
                recalculate()
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
        previewTask?.cancel()
        request.playback.pauseForEditing()
        guard request.vm.applyTimelineEdits(.init(edits: edits, actionName: "Remove Silence")) else {
            error = request.vm.detailMessage
            return false
        }
        preparingPreview = false
        skipSilence = false
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
        if !request.vm.applyTimelineEdits(.init(edits: edits, actionName: "Restore Silence")) {
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

    func changeThresholdMode() {
        if automaticThreshold { threshold = SilenceDetection.suggestedThreshold(windows) }
        recalculate()
    }

    private func configuration() -> SilenceDetectionRequest {
        .init(
            audioURL: sourceURL ?? URL(fileURLWithPath: "/"), takeDuration: duration, sourceOffset: sourceOffset,
            minimumSilence: minimumDuration, thresholdDB: threshold, previousCuts: cuts,
            paddingBefore: paddingBefore, paddingAfter: paddingAfter, minimumAudio: minimumAudio)
    }

    func recalculate() {
        guard active, !loading, !windows.isEmpty else { return }
        calculationTask?.cancel()
        error = nil
        calculating = true
        let windows = windows
        let configuration = configuration()
        let noCuts = intensity == 0 && !customized
        calculationTask = Task {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            let task = Task.detached(priority: .userInitiated) {
                noCuts
                    ? configuration.previousCuts.filter { $0.source == .user }
                    : SilenceDetection.cuts(.init(windows: windows, configuration: configuration))
            }
            let result = await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
            guard !Task.isCancelled else { return }
            cuts = result
            calculating = false
            updateMetrics()
            if skipSilence { updatePreview() }
        }
    }

    func keep(_ range: EditorTimeRange) {
        var edits = TimelineEdits.empty
        edits.cuts = cuts
        guard let restored = EditorTimeRange.restoring(.init(range: range, edits: edits, takeDuration: duration)) else {
            return
        }
        cuts = restored.cuts
        updateMetrics()
        if skipSilence { updatePreview() }
    }

    private func updateMetrics() {
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
            do { try await Task.sleep(for: .milliseconds(220)) } catch { return }
            guard !Task.isCancelled else { return }
            await request.playback.load(
                .init(project: project, baseSettings: request.vm.settings, previewCuts: skipSilence ? proposed : nil))
            guard !Task.isCancelled else { return }
            preparingPreview = false
            if let loadError = request.playback.loadError { error = loadError }
        }
    }

}

struct SilenceInspectorPane: View {
    @Bindable var session: SilenceEditingSession

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !session.loading && !session.calculating && session.error == nil {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("\(session.metrics.pauseCount) pauses")
                                    .foregroundStyle(BlitzUI.secondaryText)
                                Spacer(minLength: 8)
                                Text("\(SilenceTime.label(session.metrics.removedDuration)) shorter")
                                    .foregroundStyle(BlitzUI.mint)
                            }
                            if session.metrics.hasChanges {
                                Text("\(SilenceTime.label(session.metrics.outputDuration)) after removal")
                                    .foregroundStyle(BlitzUI.secondaryText)
                            }
                        }
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                    }
                    HStack {
                        Text(session.customized ? "Custom settings" : "Intensity").font(
                            .system(size: 12, weight: .semibold))
                        Spacer()
                        Button(session.customized ? "Simple" : "Customize") { session.customized.toggle() }
                            .blitzGlassButton()
                    }
                    if !session.customized {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("How tight or loose to make the cuts.").font(.system(size: 11)).foregroundStyle(
                                BlitzUI.secondaryText)
                            Slider(value: $session.intensity, in: 0...3, step: 1).accessibilityLabel(
                                "Silence intensity"
                            )
                            .onChange(of: session.intensity) { _, _ in session.changeIntensity() }
                            HStack {
                                ForEach(Array(["No cuts", "Natural", "Fast", "Super"].enumerated()), id: \.offset) {
                                    index, title in
                                    if index > 0 { Spacer(minLength: 0) }
                                    Text(title).foregroundStyle(
                                        Int(session.intensity) == index ? Color.white : BlitzUI.secondaryText)
                                }
                            }.font(.system(size: 10))
                        }.padding(.top, -14)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Threshold").font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Toggle("Auto", isOn: $session.automaticThreshold).toggleStyle(.checkbox).font(
                                .system(size: 10)
                            )
                            .onChange(of: session.automaticThreshold) { _, _ in session.changeThresholdMode() }
                        }
                        Text("Below this is considered silent.").font(.system(size: 11)).foregroundStyle(
                            BlitzUI.secondaryText)
                        HStack {
                            Slider(value: $session.threshold, in: -70 ... -15, step: 1).accessibilityLabel(
                                "Silence threshold"
                            )
                            .disabled(session.automaticThreshold)
                            .onChange(of: session.threshold) { _, _ in session.recalculate() }
                            Text("\(Int(session.threshold)) dB").font(.system(size: 11, design: .monospaced)).frame(
                                width: 48)
                        }
                    }
                    if session.customized {
                        parameter(
                            .init(
                                title: "Minimum duration", detail: "Silence longer than this will be cut.",
                                value: $session.minimumDuration, range: 0.1...3))
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Padding").font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Toggle("Link", isOn: $session.linkedPadding).toggleStyle(.checkbox).font(
                                    .system(size: 10))
                            }
                            Text("Leave space before and after speech.").font(.system(size: 11)).foregroundStyle(
                                BlitzUI.secondaryText)
                            parameter(.init(title: "Before", detail: "", value: $session.paddingBefore, range: 0...1))
                            parameter(.init(title: "After", detail: "", value: $session.paddingAfter, range: 0...1))
                        }
                        parameter(
                            .init(
                                title: "Remove short audio spikes", detail: "Cut audible clips shorter than this.",
                                value: $session.minimumAudio, range: 0...0.5))
                    }
                    if let error = session.error {
                        Text(error).font(.system(size: 11)).foregroundStyle(.red).fixedSize(
                            horizontal: false, vertical: true)
                    }
                }.padding(14)
            }
            .scrollIndicators(.hidden)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                if session.loading || session.calculating {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.mini)
                        Text(session.loading ? "Analyzing audio…" : "Updating cuts…")
                            .font(.system(size: 11)).foregroundStyle(BlitzUI.secondaryText)
                    }
                }
                HStack(spacing: 8) {
                    Toggle(
                        "Ignore silent sections",
                        isOn: Binding(
                            get: { session.skipSilence }, set: { session.setPreviewEnabled($0) }
                        )
                    )
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .disabled(session.loading || session.calculating || session.error != nil)
                    .help("Skip suggested silence during playback only. The recording and export stay unchanged.")
                    Spacer(minLength: 0)
                    if session.preparingPreview {
                        ProgressView().controlSize(.mini).help("Preparing silence preview")
                    }
                }
                if session.hasRemovedSilence && !session.metrics.hasChanges {
                    Button {
                        session.restoreSilence()
                    } label: {
                        Text("Restore removed silence").frame(maxWidth: .infinity)
                    }
                    .blitzGlassButton()
                    .disabled(session.preparingPreview)
                } else {
                    Button {
                        _ = session.apply()
                    } label: {
                        Text("Remove from timeline").frame(maxWidth: .infinity)
                    }
                    .blitzProminentGlassButton()
                    .disabled(!session.canApply)
                    .help("Remove silence and close the gaps on every track, in playback and export. Undo with ⌘Z.")
                    .contextMenu {
                        if session.hasRemovedSilence {
                            Button("Restore removed silence") { session.restoreSilence() }
                        }
                    }
                }
            }.padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BlitzUI.projectLibraryBackground)
        .buttonStyle(BlitzControlButtonStyle(isProminent: false))
        .tint(BlitzUI.mint)
        .onChange(of: session.paddingBefore) { _, value in
            if session.linkedPadding { session.paddingAfter = value }
        }
        .onChange(of: session.paddingAfter) { _, value in
            if session.linkedPadding { session.paddingBefore = value }
        }
    }

    private struct Parameter {
        let title: String
        let detail: String
        let value: Binding<Double>
        let range: ClosedRange<Double>
    }
    private func parameter(_ parameter: Parameter) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(parameter.title).font(.system(size: 12, weight: .semibold))
            if !parameter.detail.isEmpty {
                Text(parameter.detail).font(.system(size: 11)).foregroundStyle(BlitzUI.secondaryText)
            }
            HStack {
                Slider(value: parameter.value, in: parameter.range, step: 0.05).accessibilityLabel(parameter.title)
                Text("\(parameter.value.wrappedValue, specifier: "%.2f") s").font(
                    .system(size: 11, design: .monospaced)
                ).frame(width: 48)
            }.onChange(of: parameter.value.wrappedValue) { _, _ in session.recalculate() }
        }
    }
}

enum SilenceTime {
    static func label(_ seconds: Double) -> String {
        let time = max(0, seconds.isFinite ? seconds : 0)
        return String(format: "%d:%04.1f", Int(time) / 60, time.truncatingRemainder(dividingBy: 60))
    }
}

#if DEBUG
import SwiftUI

struct BlitzUIKitLoading: View {
    private let transcriptStatuses: [(String, TranscriptionJobStatus)] = [
        ("queued", .queued), ("preparingAudio", .preparingAudio), ("loadingModels", .loadingModels),
        ("transcribing", .transcribing), ("diarizing", .diarizing), ("saving", .saving),
        ("waitingForModel", .waitingForModel), ("noAudio", .noAudio), ("failed", .failed("Model download failed")),
        ("ready", .ready(URL(fileURLWithPath: "/tmp/transcript.json"))),
    ]
    private let startedAt = Date().addingTimeInterval(-42)

    var body: some View {
        BlitzUIKitSection(title: "Loading & progress", detail: "Every spinner, bar and waiting state.") {
            HStack(alignment: .top, spacing: 28) {
                BlitzUIKitSpecimen(label: "ProgressView · mini / small / regular") {
                    HStack(spacing: 16) {
                        ProgressView().controlSize(.mini)
                        ProgressView().controlSize(.small)
                        ProgressView()
                    }
                }
                BlitzUIKitSpecimen(label: "ProgressView · linear determinate / indeterminate") {
                    VStack(spacing: 10) {
                        ProgressView(value: 0.62).progressViewStyle(.linear).tint(BlitzUI.mint)
                        ProgressView().progressViewStyle(.linear).tint(BlitzUI.mint)
                    }
                    .frame(width: 220)
                }
                BlitzUIKitSpecimen(label: "ProgressView(\"Preparing preview…\")") {
                    ProgressView("Preparing preview…").controlSize(.small)
                }
            }
            BlitzUIKitGroup("Recording finish") {
                BlitzUIKitSpecimen(label: "FinishingProgressStatus · progress") {
                    FinishingProgressStatus(title: "Saving recording…", detail: "Exporting final video…",
                                            progress: 0.45, percent: "45%", startedAt: startedAt)
                        .frame(width: 320)
                }
                BlitzUIKitSpecimen(label: "FinishingProgressStatus · indeterminate") {
                    FinishingProgressStatus(title: "Saving recording…", detail: "Preparing editable project…",
                                            progress: nil, percent: "", startedAt: startedAt)
                        .frame(width: 320)
                }
                BlitzUIKitSpecimen(label: "SessionStatusText · starting") {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        SessionStatusText(title: "Starting…", detail: "Loading scene. Recording starts in…")
                    }
                }
            }
            BlitzUIKitGroup("Buttons that load") {
                BlitzUIKitSpecimen(label: "EditRecordingButton · page · loading") {
                    EditRecordingButton(configuration: .init(title: "Edit recording", isLoading: true, help: "",
                                                             placement: .page, action: {}))
                }
                BlitzUIKitSpecimen(label: "EditRecordingButton · dock") {
                    EditRecordingButton(configuration: .init(title: "Edit recording", isLoading: false, help: "",
                                                             placement: .dock, action: {}))
                }
                BlitzUIKitSpecimen(label: "ProjectLibraryActionButton · primary · loading") {
                    ProjectLibraryActionButton(configuration: .init(title: "Edit recording", systemImage: "scissors",
                                                                    tone: .primary, isLoading: true, action: {}))
                }
                BlitzUIKitSpecimen(label: "ProjectLibraryActionButton · secondary") {
                    ProjectLibraryActionButton(configuration: .init(title: "Copy AI context", systemImage: "doc.on.doc",
                                                                    tone: .secondary, isLoading: false, action: {}))
                }
            }
            BlitzUIKitGroup("Transcription · TranscriptionActivityView") {
                ForEach(transcriptStatuses, id: \.0) { name, status in
                    BlitzUIKitSpecimen(label: name) {
                        TranscriptionActivityView(configuration: .init(
                            status: status, detail: status.isRunning ? "Lesson 01 · trailer" : nil,
                            startedAt: status.isRunning ? startedAt : nil
                        ))
                        .frame(width: 240, alignment: .leading)
                    }
                }
            }
            BlitzUIKitGroup("Sharing upload · HostedVideoProgressView") {
                ForEach(Array(sharingStages.enumerated()), id: \.offset) { _, stage in
                    BlitzUIKitSpecimen(label: "stage \(stage.stage) · \(stage.title)") {
                        HostedVideoProgressView(presentation: stage).frame(width: 300)
                    }
                }
            }
            BlitzUIKitGroup("Preview placeholders · PreviewUnavailableOverlay (AppKit)") {
                BlitzUIKitSpecimen(label: "screen · starting") {
                    BlitzUIKitPreviewOverlay(kind: .screen, message: "Starting screen preview")
                        .frame(width: 220, height: 124).background(.black)
                }
                BlitzUIKitSpecimen(label: "camera · message") {
                    BlitzUIKitPreviewOverlay(kind: .camera, message: "Camera is in use by another app")
                        .frame(width: 220, height: 124).background(.black)
                }
                BlitzUIKitSpecimen(label: "camera · compact") {
                    BlitzUIKitPreviewOverlay(kind: .camera, message: "No camera")
                        .frame(width: 64, height: 124).background(.black)
                }
            }
            BlitzUIKitGroup("Silence analysis · SilenceSummaryCard phases") {
                ForEach(BlitzUIKitSilence.phases, id: \.0) { name, phase in
                    BlitzUIKitSpecimen(label: name) {
                        SilenceSummaryCard(presentation: BlitzUIKitSilence.presentation(phase), phaseStartedAt: startedAt)
                            .frame(width: 330)
                    }
                }
            }
        }
    }

    private var sharingStages: [HostedVideoProgressPresentation] {
        [
            .init(stage: 0, title: "Saving cloud copy", detail: "Rendering a browser-ready H.264 copy, up to 1080p.", fraction: 0.3),
            .init(stage: 1, title: "Uploading video", detail: "84 MB of 212 MB", fraction: 0.4),
            .init(stage: 2, title: "Preparing playback", detail: "Your link works in a few seconds.", fraction: nil),
        ]
    }
}

enum BlitzUIKitSilence {
    static let phases: [(String, SilencePanePresentation.Phase)] = [
        ("scanning", .scanning(fraction: 0.38)), ("analyzingSpeech", .analyzingSpeech(step: 2, title: "Finding words")),
        ("proposed", .proposed), ("applied", .applied), ("noPauses", .noPauses),
        ("unavailable", .unavailable("This recording has no audio track.")),
    ]

    static func presentation(_ phase: SilencePanePresentation.Phase) -> SilencePanePresentation {
        let columns = (0..<SilenceStripColumns.count).map { index in
            let level = 0.25 + 0.7 * abs(sin(Double(index) / 6))
            return SilenceStripColumn(level: level, kept: index % 17 < 3 ? 0 : 1)
        }
        let none = phase == .noPauses
        return .init(
            phase: phase, originalDuration: 317, editedDuration: none ? 317 : 281, removedDuration: none ? 0 : 36,
            pauseCount: none ? 0 : 12,
            cutRanges: [12...14, 80...83.5, 190...192], columns: columns, hasAppliedCuts: phase == .applied,
            isUpdating: false, previewEnabled: true, strength: .balanced, canApply: phase == .proposed,
            warning: nil, sourceName: "Microphone"
        )
    }
}

struct BlitzUIKitAnimations: View {
    @State private var countdown = 3
    @State private var showsToast = true
    @State private var flip = false
    @State private var percent = 12
    @State private var levels = TrackLevels(capacity: 32)

    var body: some View {
        BlitzUIKitSection(title: "Animations", detail: "Live loops. Everything here moves on its own or on click.") {
            BlitzUIKitGroup("Recording") {
                BlitzUIKitSpecimen(label: "RecordingHUDDot · blink") { RecordingHUDDot().padding(8) }
                BlitzUIKitSpecimen(label: ".symbolEffect(.pulse) · sidebar Record") {
                    Image(systemName: "record.circle.fill")
                        .font(BlitzType.symbol(18))
                        .foregroundStyle(BlitzUI.recordRed)
                        .symbolEffect(.pulse, options: .repeating, isActive: true)
                }
                BlitzUIKitSpecimen(label: "ElapsedTimeText · recording / paused") {
                    VStack(alignment: .leading, spacing: 6) {
                        ElapsedTimeText(isPaused: false, elapsed: "02:41")
                        ElapsedTimeText(isPaused: true, elapsed: "02:41")
                    }
                }
                BlitzUIKitSpecimen(label: "BlitzLevelMeter · active / inactive") {
                    VStack(spacing: 8) {
                        BlitzLevelMeter(levels: levels, active: true).frame(width: 140, height: 22)
                        BlitzLevelMeter(levels: levels, active: false).frame(width: 140, height: 22)
                    }
                }
                BlitzUIKitSpecimen(label: "RecordingHUDMeter") {
                    RecordingHUDMeter(levels: levels, isActive: true).frame(height: 18)
                }
            }
            BlitzUIKitGroup("Countdown & numbers") {
                BlitzUIKitSpecimen(label: "RecordingCountdownOverlay · numericText") {
                    RecordingCountdownOverlay(configuration: .init(remaining: countdown, onCancel: {}))
                        .frame(width: 280, height: 220)
                        .background(BlitzUI.canvasBackground, in: .rect(cornerRadius: BlitzUI.cardRadius))
                        .clipShape(.rect(cornerRadius: BlitzUI.cardRadius))
                }
                BlitzUIKitSpecimen(label: ".contentTransition(.numericText())") {
                    Text("\(percent)%")
                        .font(BlitzType.largeTitle)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.snappy, value: percent)
                }
            }
            BlitzUIKitGroup("Transitions") {
                BlitzUIKitSpecimen(label: "toast · .move(edge: .bottom) + .opacity") {
                    ZStack(alignment: .bottom) {
                        Color.clear
                        if showsToast {
                            Label("Exported trailer-landscape.mov", systemImage: "checkmark.circle.fill")
                                .font(BlitzType.label)
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(.regularMaterial, in: .capsule)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .frame(width: 280, height: 90)
                    .clipped()
                    .animation(.snappy(duration: 0.25), value: showsToast)
                }
                BlitzUIKitSpecimen(label: "BlitzToggleStyle · easeInOut(0.16)") {
                    Toggle("Auto flip", isOn: $flip).toggleStyle(.blitzSwitchOnly)
                }
                BlitzUIKitSpecimen(label: "ProjectAIPromptButton · symbol replace on click") {
                    ProjectAIPromptButton(context: .init(projectId: UUID(), title: "trailer", recordedAt: Date(),
                                                         previewDurationSeconds: 317, previewQuality: "1080p",
                                                         sources: ["Screen", "Camera"]))
                }
            }
            BlitzUIKitGroup("Motion previews · EditorMotionPreview (TimelineView loop)") {
                ForEach(Array(motionEffects.enumerated()), id: \.offset) { _, effect in
                    BlitzUIKitSpecimen(label: effect.0) {
                        EditorMotionPreview(configuration: .init(
                            effect: effect.1,
                            source: .init(screen: nil, camera: nil, background: .graphite),
                            isAnimating: true
                        ))
                        .frame(width: 150, height: 90)
                    }
                }
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(90))
                levels.append(Float.random(in: 0.05...0.95))
            }
        }
        .task {
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                tick += 1
                countdown = countdown == 1 ? 3 : countdown - 1
                percent = (percent + 17) % 100
                if tick % 2 == 0 { showsToast.toggle() }
                if tick % 3 == 0 { flip.toggle() }
            }
        }
    }

    private var motionEffects: [(String, EditorMotionEffect)] {
        [("smoothing", .smoothing(true)), ("clicks", .clicks(true)), ("cursorSize", .cursorSize(1.6)),
         ("zoom", .zoom(amount: 1.8, enabled: true)), ("cameraFollow", .cameraFollow(true))]
    }
}
private struct BlitzUIKitPreviewOverlay: NSViewRepresentable {
    let kind: PreviewUnavailableKind
    let message: String

    func makeNSView(context: Context) -> PreviewUnavailableOverlay {
        PreviewUnavailableOverlay(kind: kind)
    }

    func updateNSView(_ view: PreviewUnavailableOverlay, context: Context) {
        view.apply(message: message)
    }
}
#endif

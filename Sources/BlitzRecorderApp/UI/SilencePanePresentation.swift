import Foundation

enum SilenceStrength: Hashable, CaseIterable {
    case off, gentle, balanced, strong

    var title: String {
        switch self {
        case .off: "Off"
        case .gentle: "Gentle"
        case .balanced: "Balanced"
        case .strong: "Strong"
        }
    }

    var detail: String {
        switch self {
        case .off: "No automatic cuts. Pauses you cut by hand stay cut."
        case .gentle: "Trims long pauses and keeps a natural rhythm."
        case .balanced: "Tightens every pause for a quicker pace."
        case .strong: "Leaves almost no space between phrases."
        }
    }

    var pacing: SilencePacing? {
        switch self {
        case .off: nil
        case .gentle: .natural
        case .balanced: .tight
        case .strong: .rapid
        }
    }

    init(_ pacing: SilencePacing) {
        switch pacing {
        case .natural: self = .gentle
        case .tight: self = .balanced
        case .rapid: self = .strong
        }
    }
}

struct SilenceStripColumn: Equatable {
    let level: Double
    let kept: Double
}

enum SilenceStripColumns {
    static let count = 120

    struct Request {
        let windows: [SilenceWindow]
        let duration: Double
        let cuts: [ClosedRange<Double>]
    }

    static func make(_ request: Request) -> [SilenceStripColumn] {
        guard request.duration > 0, !request.windows.isEmpty else { return [] }
        let width = request.duration / Double(count)
        var peaks = [Double](repeating: -120, count: count)
        for window in request.windows {
            let index = min(count - 1, max(0, Int(window.start / width)))
            peaks[index] = max(peaks[index], window.decibels)
        }
        let cuts = request.cuts.sorted { $0.lowerBound < $1.lowerBound }
        var cutIndex = 0
        return (0..<count).map { index in
            let start = Double(index) * width
            let end = start + width
            while cutIndex < cuts.count, cuts[cutIndex].upperBound <= start { cutIndex += 1 }
            var removed = 0.0
            var probe = cutIndex
            while probe < cuts.count, cuts[probe].lowerBound < end {
                removed += max(0, min(end, cuts[probe].upperBound) - max(start, cuts[probe].lowerBound))
                probe += 1
            }
            let level = min(1, max(0, (peaks[index] + 60) / 50))
            return .init(level: level, kept: max(0, 1 - removed / width))
        }
    }
}

struct SilencePanePresentation: Equatable {
    enum Phase: Equatable {
        case scanning(fraction: Double)
        case analyzingSpeech(step: Int, title: String)
        case unavailable(String)
        case noPauses
        case proposed
        case applied

        var kind: Int {
            switch self {
            case .scanning: 0
            case .analyzingSpeech(let step, _): 10 + step
            case .unavailable: 2
            case .noPauses: 3
            case .proposed: 4
            case .applied: 5
            }
        }

        var showsFooter: Bool {
            switch self {
            case .unavailable, .noPauses: false
            default: true
            }
        }
    }

    let phase: Phase
    let originalDuration: Double
    let editedDuration: Double
    let removedDuration: Double
    let pauseCount: Int
    let cutRanges: [ClosedRange<Double>]
    let columns: [SilenceStripColumn]
    let hasAppliedCuts: Bool
    let isUpdating: Bool
    let previewEnabled: Bool
    let strength: SilenceStrength?
    let canApply: Bool
    let warning: String?
    let sourceName: String

    var isWorking: Bool {
        switch phase {
        case .scanning, .analyzingSpeech: true
        default: false
        }
    }

    var hasResult: Bool {
        switch phase {
        case .proposed, .applied, .noPauses: true
        default: false
        }
    }

    var shorterPercent: Int {
        guard originalDuration > 0 else { return 0 }
        return Int((removedDuration / originalDuration * 100).rounded())
    }

    var strengthDetail: String {
        strength?.detail ?? "Custom settings from Fine-tune."
    }

    struct TimeRequest {
        let elapsed: TimeInterval
    }

    func progressLine(_ request: TimeRequest) -> String {
        switch phase {
        case .scanning(let fraction):
            if request.elapsed >= 2, fraction >= 0.05, fraction < 1 {
                let remaining = request.elapsed / fraction * (1 - fraction)
                return remaining < 60
                    ? "About \(max(1, Int(remaining.rounded()))) s left"
                    : "About \(Int((remaining / 60).rounded(.up))) min left"
            }
            return "Reading \(sourceName.lowercased())"
        case .analyzingSpeech(let step, _):
            let elapsed = request.elapsed >= 2 ? " · \(ClockDuration.label(request.elapsed))" : ""
            return "Step \(step) of 4\(elapsed)"
        default:
            return ""
        }
    }

    struct Request {
        let loading: Bool
        let scanProgress: Double?
        let waitingForTranscript: Bool
        let transcriptStatus: TranscriptionJobStatus?
        let hasAudio: Bool
        let error: String?
        let hasChanges: Bool
        let hasRemovedSilence: Bool
        let isUpdating: Bool
        let duration: Double
        let metrics: SilenceTimelineMetrics
        let cuts: [TimelineCut]
        let windows: [SilenceWindow]
        let previewEnabled: Bool
        let suggestsPauses: Bool
        let customized: Bool
        let intensity: Double
        let canApply: Bool
        let sourceName: String
    }

    static func make(_ request: Request) -> SilencePanePresentation {
        let phase: Phase
        var warning = request.error
        if request.loading {
            phase = .scanning(fraction: request.scanProgress ?? 0)
        } else if request.waitingForTranscript {
            phase = speechPhase(request.transcriptStatus)
        } else if !request.hasAudio {
            phase = .unavailable(request.error ?? "Silence removal needs a recording with a readable audio track.")
            warning = nil
        } else if request.hasChanges {
            phase = request.metrics.pauseCount == 0 && !request.hasRemovedSilence ? .noPauses : .proposed
        } else if request.hasRemovedSilence {
            phase = .applied
        } else {
            phase = .noPauses
        }
        if request.metrics.outputDuration < 0.1, request.hasChanges, request.hasAudio, !request.loading {
            warning = "These settings would cut the whole recording. Pick a gentler strength."
        }
        let strength: SilenceStrength?
        if !request.suggestsPauses {
            strength = .off
        } else if request.customized {
            strength = nil
        } else {
            strength = SilencePacing(rawValue: Int(request.intensity.rounded())).map(SilenceStrength.init)
        }
        let cutRanges = request.cuts.filter { $0.isEnabled && $0.kind == .silence && $0.end > $0.start }
            .map { $0.start...$0.end }
        return .init(
            phase: phase,
            originalDuration: request.duration,
            editedDuration: request.metrics.outputDuration,
            removedDuration: request.metrics.removedDuration,
            pauseCount: request.metrics.pauseCount,
            cutRanges: cutRanges,
            columns: SilenceStripColumns.make(.init(windows: request.windows, duration: request.duration, cuts: cutRanges)),
            hasAppliedCuts: request.hasRemovedSilence,
            isUpdating: request.isUpdating,
            previewEnabled: request.previewEnabled,
            strength: strength,
            canApply: request.canApply,
            warning: warning,
            sourceName: request.sourceName
        )
    }

    private static func speechPhase(_ status: TranscriptionJobStatus?) -> Phase {
        switch status {
        case .loadingModels: .analyzingSpeech(step: 2, title: "Loading speech model")
        case .transcribing: .analyzingSpeech(step: 3, title: "Finding words")
        case .diarizing, .saving: .analyzingSpeech(step: 4, title: "Finishing up")
        default: .analyzingSpeech(step: 1, title: "Preparing audio")
        }
    }
}

extension SilenceEditingSession {
    var presentation: SilencePanePresentation {
        .make(.init(
            loading: loading, scanProgress: scanProgress, waitingForTranscript: waitingForTranscript,
            transcriptStatus: transcriptStatus, hasAudio: !windows.isEmpty, error: error,
            hasChanges: hasChanges, hasRemovedSilence: hasRemovedSilence,
            isUpdating: calculating || preparingPreview, duration: duration, metrics: metrics, cuts: cuts, windows: windows,
            previewEnabled: skipSilence, suggestsPauses: suggestsPauses, customized: customized,
            intensity: intensity, canApply: canApply, sourceName: sourceName
        ))
    }

    func selectStrength(_ strength: SilenceStrength) {
        guard let pacing = strength.pacing else {
            setSuggestionsEnabled(false)
            return
        }
        if !suggestsPauses { setSuggestionsEnabled(true) }
        selectPacing(pacing)
    }
}

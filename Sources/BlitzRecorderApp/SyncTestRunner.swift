import AppKit
import AVFoundation

/// Records a two-minute test take that claps every couple of seconds: the screen flashes white and the speakers
/// beep. Meanwhile it pauses and resumes, re-applies the screen source and hides the app for a moment, the moments
/// that have put tracks out of sync before. Afterwards it finds every clap in every track and reports how far each
/// one is from the screen, whether that changed during the take and whether it jumped.
@MainActor
final class SyncTestRunner {
    static let shared = SyncTestRunner()
    static let durationSeconds = 120.0
    nonisolated static let resultFileName = "sync-test.json"

    private(set) var isRunning = false

    private struct Step {
        let at: Double
        let run: @MainActor (RecorderCoordinator) -> Void
        let name: String
    }

    /// No clap lands within this many seconds of a step, which can hide the flash or drop a beep on purpose.
    private static let quietAroundSteps = 0.8
    private static let hiddenSeconds = 90.0...91.5
    private static let steps: [Step] = [
        .init(at: 30, run: { $0.pause() }, name: "pause"),
        .init(at: 33, run: { $0.resume() }, name: "resume"),
        .init(at: 60, run: { coordinator in
            if let binding = coordinator.settings.screenSourceBinding { coordinator.setScreenSource(binding) }
        }, name: "re-apply the screen source"),
        .init(at: hiddenSeconds.lowerBound, run: { $0.setRecorderUIIncluded(false) }, name: "hide the app"),
        .init(at: hiddenSeconds.upperBound, run: { $0.setRecorderUIIncluded(true) }, name: "show the app"),
    ]

    func run(_ coordinator: RecorderCoordinator) {
        guard !isRunning, coordinator.state == .idle else { return }
        isRunning = true
        Task {
            await perform(coordinator)
            isRunning = false
        }
    }

    private func perform(_ coordinator: RecorderCoordinator) async {
        let showedApp = coordinator.settings.includesRecorderUI
        if !showedApp { coordinator.setRecorderUIIncluded(true) }
        defer { if !showedApp { coordinator.setRecorderUIIncluded(false) } }
        let window = SyncTestFlashWindow(screen: Self.recordedScreen(coordinator.settings))
        window.show()
        defer { window.close() }
        let beeper = SyncTestBeeper()

        CaptureLog.note("Sync test: starting a \(Int(Self.durationSeconds)) s take")
        coordinator.start(takeTitle: "Sync test")
        guard await waitFor(seconds: 30, { coordinator.state == .recording }), let take = coordinator.lastTake else {
            CaptureLog.note("Sync test: the take did not start")
            Self.present(["The test recording did not start. Check that a screen or camera is ready to record."])
            return
        }

        let claps = await clap(.init(coordinator: coordinator, window: window, beeper: beeper))
        if coordinator.state == .recording || coordinator.state == .paused { coordinator.stop() }
        window.showMessage("Checking sync…")
        guard await waitFor(seconds: 600, {
            coordinator.state == .idle && FileManager.default.fileExists(atPath: take.projectURL.path)
        }) else {
            Self.present(["The test recording was not saved, so it could not be checked."])
            return
        }
        let lines = await Task.detached(priority: .userInitiated) {
            await Self.analyze(.init(projectURL: take.projectURL, claps: claps))
        }.value
        Self.present(lines)
    }

    private struct ClapRequest {
        let coordinator: RecorderCoordinator
        let window: SyncTestFlashWindow
        let beeper: SyncTestBeeper?
    }

    /// Claps until the test ends or someone stops the take, and returns when each clap happened on the take timeline.
    private func clap(_ request: ClapRequest) async -> [Double] {
        let started = ContinuousClock.now
        var claps: [Double] = []
        var pending = Self.steps
        var nextClap = 3.0
        var intervalIndex = 0
        while true {
            let elapsed = (ContinuousClock.now - started).seconds
            guard elapsed < Self.durationSeconds,
                  [.recording, .paused].contains(request.coordinator.state) else { break }
            if let step = pending.first, elapsed >= step.at {
                pending.removeFirst()
                CaptureLog.note("Sync test: \(step.name) at \(String(format: "%.1f", elapsed)) s")
                step.run(request.coordinator)
            }
            if elapsed >= nextClap {
                let nearStep = Self.steps.contains { abs($0.at - elapsed) < Self.quietAroundSteps }
                let isHidden = elapsed > Self.hiddenSeconds.lowerBound
                    && elapsed < Self.hiddenSeconds.upperBound + Self.quietAroundSteps
                if request.coordinator.state == .recording, !nearStep, !isHidden {
                    request.window.flash()
                    request.beeper?.beep()
                    claps.append(request.coordinator.recordingTimelineSeconds)
                }
                nextClap += SyncTestAnalysis.clapIntervals[intervalIndex % SyncTestAnalysis.clapIntervals.count]
                intervalIndex += 1
            }
            request.window.showMessage(Self.message(remaining: Self.durationSeconds - elapsed))
            try? await Task.sleep(for: .milliseconds(5))
        }
        return claps
    }

    private static func message(remaining: Double) -> String {
        "Sync test · \(Int(max(0, remaining).rounded(.up))) s left\n"
            + "Keep this screen in view and the sound on. Point your camera at the screen to check it too."
    }

    private func waitFor(seconds: Double, _ condition: @MainActor () -> Bool) async -> Bool {
        let started = ContinuousClock.now
        while !condition() {
            guard (ContinuousClock.now - started).seconds < seconds else { return false }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return true
    }

    private static func recordedScreen(_ settings: RecordingSettings) -> NSScreen? {
        guard let id = settings.screenSourceBinding?.displayID ?? settings.selectedDisplayID else { return NSScreen.main }
        return NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue == id
        } ?? NSScreen.main
    }

    private static func present(_ lines: [String]) {
        NSApp.activate()
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Sync test"
            alert.informativeText = lines.joined(separator: "\n\n")
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    // MARK: Analysis

    struct AnalysisRequest: Sendable {
        let projectURL: URL
        let claps: [Double]
    }

    struct TrackResult: Codable, Equatable {
        let role: String
        let name: String
        let found: Int
        let claps: Int
        let offset: Double?
        let drift: Double?
        let largestStep: Double?
        let isInSync: Bool?
    }

    nonisolated private static let roles: [(role: String, mediaType: AVMediaType)] = [
        ("screen", .video), ("camera", .video), ("microphone", .audio), ("systemAudio", .audio),
    ]

    nonisolated static func analyze(_ request: AnalysisRequest) async -> [String] {
        guard let project = try? TakeFileStore().loadRecordingProject(at: request.projectURL) else {
            return ["The test recording could not be read."]
        }
        var timings: [(role: String, url: URL, timing: SyncTestAnalysis.TrackTiming?)] = []
        for (role, mediaType) in roles {
            guard let source = project.sources.first(where: { $0.role == role && $0.exists }) else { continue }
            let url = URL(fileURLWithPath: source.path)
            let shift = project.sourceOffset(forRole: role)
            let onsets: [Double]
            if mediaType == .video {
                onsets = SyncTestAnalysis.flashOnsets((try? await SyncTestMedia.brightness(url)) ?? [])
            } else {
                onsets = SyncTestAnalysis.toneOnsets(.init(
                    samples: (try? await SyncTestMedia.sound(url)) ?? [], sampleRate: SyncTestMedia.sampleRate
                ))
            }
            let timing = SyncTestAnalysis.match(.init(claps: request.claps, onsets: onsets.map { $0 + shift }))
            timings.append((role, url, timing))
        }
        guard let reference = timings.first(where: { $0.timing != nil }), let referenceTiming = reference.timing else {
            CaptureLog.note("Sync test: no clap was found in any track (\(request.claps.count) claps made)")
            return ["No clap was found in the recording. Record a display with the sound on, then try again."]
        }
        let referenceName = TakeSyncReport.trackName(reference.url.lastPathComponent).lowercased()
        var lines: [String] = []
        var results: [TrackResult] = []
        for entry in timings {
            let name = TakeSyncReport.trackName(entry.url.lastPathComponent)
            guard let timing = entry.timing else {
                lines.append("\(name): no clap found. \(missingClapAdvice(role: entry.role))")
                results.append(.init(role: entry.role, name: name, found: 0, claps: request.claps.count,
                                     offset: nil, drift: nil, largestStep: nil, isInSync: nil))
                continue
            }
            if entry.role == reference.role {
                results.append(.init(role: entry.role, name: name, found: timing.matched.count, claps: request.claps.count,
                                     offset: 0, drift: 0, largestStep: 0, isInSync: true))
                continue
            }
            guard let comparison = SyncTestAnalysis.compare(.init(track: timing, reference: referenceTiming)) else {
                lines.append("\(name): too few claps found next to the \(referenceName) to compare.")
                continue
            }
            let line = describe(.init(name: name, referenceName: referenceName, comparison: comparison))
            lines.append(line)
            results.append(.init(
                role: entry.role, name: name, found: comparison.matched, claps: comparison.claps,
                offset: comparison.offset, drift: comparison.drift, largestStep: comparison.largestStep,
                isInSync: comparison.isInSync
            ))
            TakeSyncJournal.record(.init(
                trackURL: entry.url, kind: .syncTest, at: nil, seconds: comparison.offset,
                detail: comparison.isInSync ? nil : line
            ))
        }
        if lines.isEmpty { lines.append("Only the \(referenceName) showed the claps, so there was nothing to compare.") }
        let takeDirectory = request.projectURL.deletingLastPathComponent()
        if let data = try? JSONEncoder().encode(results) {
            try? data.write(to: takeDirectory.appendingPathComponent(resultFileName), options: .atomic)
        }
        CaptureLog.note("Sync test: \(request.claps.count) claps; " + lines.joined(separator: " "))
        return lines
    }

    nonisolated private static func missingClapAdvice(role: String) -> String {
        switch role {
        case "camera": "Point the camera at the screen to check it."
        case "microphone": "Use speakers, not headphones, so the microphone hears the beeps."
        case "systemAudio": "Turn the sound on so the beeps are recorded."
        default: "Record a display, not a window, so the flashes are captured."
        }
    }

    private struct Description {
        let name: String
        let referenceName: String
        let comparison: SyncTestAnalysis.Comparison
    }

    nonisolated private static func describe(_ description: Description) -> String {
        let comparison = description.comparison
        let milliseconds = Int((abs(comparison.offset) * 1_000).rounded())
        let position = milliseconds == 0 ? "lined up with the \(description.referenceName)"
            : "\(milliseconds) ms \(comparison.offset > 0 ? "after" : "before") the \(description.referenceName)"
        let steadiness = comparison.isSteady
            ? "steady through the test"
            : String(format: "moved %.0f ms during the test, up to %.0f ms at once",
                     abs(comparison.drift) * 1_000, comparison.largestStep * 1_000)
        return "\(description.name): \(position), \(steadiness), "
            + "\(comparison.matched) of \(comparison.claps) claps. \(comparison.isInSync ? "In sync." : "Out of sync.")"
    }
}

private extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}

/// A dark window over the recorded screen that flashes white for each clap. White and black here are the test
/// signal, not app chrome.
@MainActor
final class SyncTestFlashWindow {
    private let window: NSWindow
    private let label = NSTextField(labelWithString: "")
    private static let dark = NSColor(white: 0.06, alpha: 1)
    private var flashTask: Task<Void, Never>?

    init(screen: NSScreen?) {
        let frame = screen?.frame ?? NSScreen.main?.frame ?? .init(x: 0, y: 0, width: 1280, height: 800)
        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .floating
        window.backgroundColor = Self.dark
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        label.font = .systemFont(ofSize: 18, weight: .medium)
        label.textColor = NSColor(white: 0.55, alpha: 1)
        label.alignment = .center
        label.maximumNumberOfLines = 3
        label.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView(frame: NSRect(origin: .zero, size: frame.size))
        content.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -80),
            label.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor, multiplier: 0.8),
        ])
        window.contentView = content
    }

    func show() {
        window.orderFrontRegardless()
    }

    func showMessage(_ text: String) {
        guard label.stringValue != text else { return }
        label.stringValue = text
    }

    func flash() {
        flashTask?.cancel()
        window.backgroundColor = .white
        window.display()
        flashTask = Task { @MainActor [window] in
            try? await Task.sleep(for: .milliseconds(100))
            window.backgroundColor = Self.dark
            window.display()
        }
    }

    func close() {
        flashTask?.cancel()
        window.orderOut(nil)
    }
}

/// Plays the clap beep: 100 ms of the test tone through the default output.
@MainActor
final class SyncTestBeeper {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let buffer: AVAudioPCMBuffer

    init?() {
        let format = engine.outputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0,
              let mono = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: AVAudioFrameCount(mono.sampleRate * 0.1)),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = buffer.frameCapacity
        let ramp = Int(mono.sampleRate * 0.003)
        let count = Int(buffer.frameLength)
        for index in 0..<count {
            let edge = min(1, Double(min(index, count - 1 - index)) / Double(ramp))
            samples[index] = Float(0.5 * edge * sin(2 * Double.pi * SyncTestAnalysis.toneFrequency * Double(index) / mono.sampleRate))
        }
        self.buffer = buffer
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: mono)
        do { try engine.start() } catch { return nil }
        player.play()
    }

    func beep() {
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
    }
}

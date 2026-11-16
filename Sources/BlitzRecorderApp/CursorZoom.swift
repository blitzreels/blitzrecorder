import AppKit
import ScreenCaptureKit

struct RecordingCursorSample: Codable, Sendable {
    let time: Double
    let x: Double
    let y: Double
    let clicked: Bool
    var visible: Bool = true
    var rendered: Bool = false
    var segment: Int = 0
}

extension RecordingCursorSample {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        time = try values.decode(Double.self, forKey: .time)
        x = try values.decode(Double.self, forKey: .x)
        y = try values.decode(Double.self, forKey: .y)
        clicked = try values.decode(Bool.self, forKey: .clicked)
        visible = try values.decodeIfPresent(Bool.self, forKey: .visible) ?? true
        rendered = try values.decodeIfPresent(Bool.self, forKey: .rendered) ?? false
        segment = try values.decodeIfPresent(Int.self, forKey: .segment) ?? 0
    }
}

struct RecordingCursorTrack: Codable, Sendable {
    let version: Int
    let samples: [RecordingCursorSample]

    var supportsPresentation: Bool { version == 2 && samples.contains(where: \.rendered) }
}

enum CursorCapturePolicy {
    struct Request {
        let settings: RecordingSettings
        let filter: SCContentFilter?
    }

    static func rendersCursor(_ request: Request) -> Bool {
        guard request.settings.savesSourceFiles, request.settings.includeCursor else { return false }
        if let filter = request.filter {
            if #available(macOS 15.2, *) { return filter.style == .display }
            return false
        }
        return request.settings.screenSourceBinding == nil || request.settings.screenSourceBinding?.kind == .display
    }
}

@MainActor
final class RecordingCursorTracker {
    struct Configuration {
        let settings: RecordingSettings
        let filter: SCContentFilter?
    }
    private var configuration: Configuration?
    private var samples: [RecordingCursorSample] = []
    private var privacySignals: [RecordingPrivacySignal] = []
    private var tick = 0
    private var timer: Timer?
    private var directory: URL?
    private var wasPressed = false
    private var segment = 0
    private var captureFrameProvider: (@MainActor () -> CGRect?)?
    /// A recorded window's position, asked of WindowServer ten times a second instead of on every sample.
    private var cachedWindowFrame: (checkedAt: CFTimeInterval, frame: CGRect?)?
    private var isScanningWindows = false
    private var generation = 0
    private static let windowFrameRefreshInterval: CFTimeInterval = 0.1
    private static let windowScanQueue = DispatchQueue(label: "blitzrecorder.privacy-window-scan", qos: .utility)

    struct StartRequest {
        let directory: URL
        let configuration: Configuration
        let captureFrame: @MainActor () -> CGRect?
        let time: @MainActor () -> Double?
    }
    func start(_ request: StartRequest) {
        stop()
        directory = request.directory
        configuration = request.configuration
        captureFrameProvider = request.captureFrame
        samples = []
        privacySignals = []
        tick = 0
        segment = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let time = request.time() else { return }
                self.sample(time)
            }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    func update(_ configuration: Configuration) {
        self.configuration = configuration
        segment += 1
        cachedWindowFrame = nil
    }
    /// Stops sampling at once and writes the cursor and privacy files off the main thread: a long take holds
    /// hundreds of thousands of samples. Await the returned task before reading those files.
    @discardableResult
    func stop() -> Task<Void, Never> {
        timer?.invalidate()
        timer = nil
        generation += 1
        let directory = directory
        let samples = samples
        let privacySignals = privacySignals
        self.directory = nil
        self.samples = []
        self.privacySignals = []
        wasPressed = false
        captureFrameProvider = nil
        cachedWindowFrame = nil
        isScanningWindows = false
        guard let directory, !samples.isEmpty || !privacySignals.isEmpty else { return Task {} }
        return Task.detached(priority: .userInitiated) {
            Self.write(.init(directory: directory, samples: samples, privacySignals: privacySignals))
        }
    }

    private struct TrackFiles: Sendable {
        let directory: URL
        let samples: [RecordingCursorSample]
        let privacySignals: [RecordingPrivacySignal]
    }

    nonisolated private static func write(_ files: TrackFiles) {
        guard FileManager.default.fileExists(atPath: files.directory.path) else { return }
        if !files.samples.isEmpty {
            try? JSONEncoder().encode(RecordingCursorTrack(version: 2, samples: files.samples))
                .write(to: files.directory.appendingPathComponent("cursor-track.json"), options: .atomic)
        }
        if !files.privacySignals.isEmpty {
            try? JSONEncoder().encode(RecordingPrivacySignalTrack(version: 1, signals: files.privacySignals))
                .write(to: files.directory.appendingPathComponent(RecordingPrivacySignalTrack.fileName), options: .atomic)
        }
    }
    private func sample(_ time: Double) {
        let sourceFrame = captureFrameProvider?()
        guard let config = configuration, config.settings.enabledSources.contains(.screen),
              let frame = sourceFrame ?? cachedCaptureFrame(config), frame.width > 0, frame.height > 0,
              let location = CGEvent(source: nil)?.location else { return }
        let pressed = CGEventSource.buttonState(.combinedSessionState, button: .left)
        defer { wasPressed = pressed }
        let crop = sourceFrame == nil ? ScreenCaptureGeometry.effectiveCrop(for: config.settings)
            ?? CGRect(x: 0, y: 0, width: 1, height: 1) : CGRect(x: 0, y: 0, width: 1, height: 1)
        guard crop.width > 0, crop.height > 0 else { return }
        let x = ((location.x - frame.minX) / frame.width - crop.minX) / crop.width
        let y = ((location.y - frame.minY) / frame.height - crop.minY) / crop.height
        tick += 1
        if tick % 30 == 0 { recordSensitiveWindows(.init(time: time, frame: frame, crop: crop)) }
        let visible = frame.contains(location) && (0...1).contains(x) && (0...1).contains(y)
        samples.append(.init(time: time, x: x, y: y, clicked: visible && pressed && !wasPressed,
            visible: visible && config.settings.includeCursor,
            rendered: CursorCapturePolicy.rendersCursor(.init(settings: config.settings, filter: config.filter)),
            segment: segment))
    }
    private struct SignalRequest {
        let time: Double
        let frame: CGRect
        let crop: CGRect
    }

    /// Lists the windows on screen off the main thread; a scan still running skips the next one.
    private func recordSensitiveWindows(_ request: SignalRequest) {
        guard !isScanningWindows else { return }
        isScanningWindows = true
        let generation = generation
        Self.windowScanQueue.async { [weak self] in
            let windows = SensitiveWindowScanner.visibleWindows()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.generation == generation else { return }
                    self.isScanningWindows = false
                    self.appendSensitiveWindows(.init(request: request, windows: windows))
                }
            }
        }
    }

    private struct ScannedWindows {
        let request: SignalRequest
        let windows: [SensitiveWindowScanner.Window]
    }

    private func appendSensitiveWindows(_ scanned: ScannedWindows) {
        let request = scanned.request
        for window in scanned.windows {
            let normalized = CGRect(
                x: ((window.bounds.minX - request.frame.minX) / request.frame.width - request.crop.minX) / request.crop.width,
                y: ((window.bounds.minY - request.frame.minY) / request.frame.height - request.crop.minY) / request.crop.height,
                width: window.bounds.width / request.frame.width / request.crop.width,
                height: window.bounds.height / request.frame.height / request.crop.height
            ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            guard !normalized.isNull, normalized.width > 0.01, normalized.height > 0.01 else { continue }
            privacySignals.append(.init(time: request.time, kind: window.kind, app: window.app,
                                        windowID: window.windowID, frame: normalized))
        }
    }

    private func cachedCaptureFrame(_ config: Configuration) -> CGRect? {
        let now = CACurrentMediaTime()
        if let cached = cachedWindowFrame, now - cached.checkedAt < Self.windowFrameRefreshInterval {
            return cached.frame
        }
        let frame = captureFrame(config)
        cachedWindowFrame = (now, frame)
        return frame
    }

    private func captureFrame(_ config: Configuration) -> CGRect? {
        var windowID = config.settings.screenSourceBinding?.windowID
        if let filter = config.filter {
            if #available(macOS 15.2, *) {
                if filter.style == .window { windowID = filter.includedWindows.first?.windowID }
                else if filter.style == .display { return filter.includedDisplays.first?.frame }
                else { return nil }
            } else { return nil }
        }
        if let windowID {
            guard let entries = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]],
                  let bounds = entries.first?[kCGWindowBounds as String] as? [String: Any] else { return nil }
            return CGRect(dictionaryRepresentation: bounds as CFDictionary)
        }
        guard config.settings.screenSourceBinding?.kind != .application else { return nil }
        let displayID = config.settings.selectedDisplayID.flatMap(UInt32.init) ?? CGMainDisplayID()
        return CGDisplayBounds(displayID)
    }
}

enum CursorZoomPlanning {
    struct Request {
        let samples: [RecordingCursorSample]
        let duration: Double
        let trimOffset: Double
        let cuts: [TimelineCut]
        let magnification: Double
    }
    struct PositionRequest {
        let sample: RecordingCursorSample
        let amount: Double
    }

    static func position(_ request: PositionRequest) -> CGPoint {
        CGPoint(x: min(1, max(-1, (request.sample.x - 0.5) * 2 / max(0.01, request.amount))),
                y: min(1, max(-1, (request.sample.y - 0.5) * 2 / max(0.01, request.amount))))
    }

    struct ManualZoomRequest {
        let track: ScreenZoomTrack
        let time: Double
        let duration: Double
        let magnification: Double
        let cursorSamples: [RecordingCursorSample]
        let trimOffset: Double
    }

    static let manualZoomLength = 3.0

    static func canAddZoom(_ request: ManualZoomRequest) -> Bool {
        let end = request.time + manualZoomLength
        guard request.time >= 0, end <= request.duration + 0.01 else { return false }
        if request.track.isActive, request.track.sample(at: request.time).amount > 0.01 { return false }
        return !request.track.keyframes.contains { $0.time > request.time - 0.2 && $0.time < end + 0.2 && $0.amount > 0.001 }
    }

    static func addingZoom(_ request: ManualZoomRequest) -> ScreenZoomTrack {
        let amount = ScreenZoomTrack.amount(forMagnification: request.magnification)
        let peak = request.time + 0.4
        let focus = request.cursorSamples
            .filter { $0.visible && $0.x.isFinite && $0.y.isFinite }
            .min { abs($0.time - request.trimOffset - peak) < abs($1.time - request.trimOffset - peak) }
        let position = focus.flatMap { abs($0.time - request.trimOffset - peak) < 2 ? $0 : nil }
            .map { Self.position(.init(sample: $0, amount: amount)) } ?? .zero
        var track = request.track
        let end = request.time + manualZoomLength
        track.keyframes += [
            .init(time: request.time, amount: 0, position: position),
            .init(time: peak, amount: amount, position: position),
            .init(time: end - 0.4, amount: amount, position: position),
            .init(time: end, amount: 0, position: position)
        ]
        track.keyframes.sort { $0.time < $1.time }
        track.isEnabled = true
        if request.track.isEmpty { track.intensity = request.magnification }
        return track
    }

    struct StrengthRequest {
        let track: ScreenZoomTrack
        let magnification: Double
    }

    static func changingStrength(_ request: StrengthRequest) -> ScreenZoomTrack {
        var track = request.track
        let amount = ScreenZoomTrack.amount(forMagnification: request.magnification)
        let previous = ScreenZoomTrack.amount(forMagnification: track.intensity)
        for index in track.keyframes.indices {
            let zoomed = track.keyframes[index].amount > 0.001
            let scale = (zoomed ? track.keyframes[index].amount : previous) / max(0.01, amount)
            let position = track.keyframes[index].position
            if zoomed { track.keyframes[index].amount = amount }
            track.keyframes[index].position = CGPoint(x: min(1, max(-1, position.x * scale)),
                                                      y: min(1, max(-1, position.y * scale)))
        }
        track.intensity = request.magnification
        return track
    }

    static func plan(_ request: Request) -> ScreenZoomTrack {
        let amount = ScreenZoomTrack.amount(forMagnification: request.magnification)
        let map = TimelineTimeMap(takeDuration: TimelineTimeMap.time(request.duration), cuts: request.cuts)
        var keyframes: [ScreenZoomKeyframe] = [.init(time: 0, amount: 0, position: .zero)]
        var lastEnd = 0.0
        let samples = request.samples.filter { $0.visible && $0.time.isFinite && $0.x.isFinite && $0.y.isFinite }
        for sample in samples where sample.clicked {
            let time = sample.time - request.trimOffset
            guard time >= lastEnd + 0.5, time < request.duration - 0.6, !map.isRemoved(takeTime: time) else { continue }
            let end = min(request.duration, time + 3)
            func position(_ sample: RecordingCursorSample) -> CGPoint {
                Self.position(.init(sample: sample, amount: amount))
            }
            keyframes.append(.init(time: max(lastEnd, time - 0.4), amount: 0, position: position(sample)))
            keyframes.append(.init(time: time + 0.15, amount: amount, position: position(sample)))
            var lastSampleTime = time + 0.15
            for follow in samples where follow.time - request.trimOffset > lastSampleTime && follow.time - request.trimOffset < end - 0.5 {
                let followTime = follow.time - request.trimOffset
                guard followTime - lastSampleTime >= 0.3 else { continue }
                keyframes.append(.init(time: followTime, amount: amount, position: position(follow)))
                lastSampleTime = followTime
            }
            let lastPosition = keyframes.last?.position ?? position(sample)
            keyframes.append(.init(time: max(lastSampleTime, end - 0.4), amount: amount, position: lastPosition))
            keyframes.append(.init(time: end, amount: 0, position: lastPosition))
            lastEnd = end
        }
        guard keyframes.count > 1 else { return .empty }
        return .init(keyframes: keyframes, generatedFromCursor: true, intensity: request.magnification)
    }
}

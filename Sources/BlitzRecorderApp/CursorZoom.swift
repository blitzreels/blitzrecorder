import AppKit
import ScreenCaptureKit

struct RecordingCursorSample: Codable, Sendable {
    let time: Double
    let x: Double
    let y: Double
    let clicked: Bool
}

struct RecordingCursorTrack: Codable, Sendable {
    let version: Int
    let samples: [RecordingCursorSample]
}

@MainActor
final class RecordingCursorTracker {
    struct Configuration {
        let settings: RecordingSettings
        let filter: SCContentFilter?
    }
    private var configuration: Configuration?
    private var samples: [RecordingCursorSample] = []
    private var timer: Timer?
    private var directory: URL?
    private var wasPressed = false

    struct StartRequest {
        let directory: URL
        let configuration: Configuration
        let time: @MainActor () -> Double?
    }
    func start(_ request: StartRequest) {
        stop()
        directory = request.directory
        configuration = request.configuration
        samples = []
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let time = request.time() else { return }
                self.sample(time)
            }
        }
    }
    func update(_ configuration: Configuration) { self.configuration = configuration }
    func stop() {
        timer?.invalidate()
        timer = nil
        if let directory, !samples.isEmpty, FileManager.default.fileExists(atPath: directory.path) {
            try? JSONEncoder().encode(RecordingCursorTrack(version: 1, samples: samples))
                .write(to: directory.appendingPathComponent("cursor-track.json"), options: .atomic)
        }
        directory = nil
        samples = []
        wasPressed = false
    }
    private func sample(_ time: Double) {
        guard let config = configuration, config.settings.enabledSources.contains(.screen),
              let frame = captureFrame(config), frame.width > 0, frame.height > 0,
              let location = CGEvent(source: nil)?.location else { return }
        let pressed = CGEventSource.buttonState(.combinedSessionState, button: .left)
        defer { wasPressed = pressed }
        guard frame.contains(location) else { return }
        let crop = config.settings.screenCrop ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        guard crop.width > 0, crop.height > 0 else { return }
        let x = ((location.x - frame.minX) / frame.width - crop.minX) / crop.width
        let y = ((location.y - frame.minY) / frame.height - crop.minY) / crop.height
        guard (0...1).contains(x), (0...1).contains(y) else { return }
        samples.append(.init(time: time, x: x, y: y, clicked: pressed && !wasPressed))
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
    static func plan(_ request: Request) -> ScreenZoomTrack {
        let amount = ScreenZoomTrack.amount(forMagnification: request.magnification)
        let map = TimelineTimeMap(takeDuration: TimelineTimeMap.time(request.duration), cuts: request.cuts)
        var keyframes: [ScreenZoomKeyframe] = [.init(time: 0, amount: 0, position: .zero)]
        var lastEnd = 0.0
        let samples = request.samples.filter { $0.time.isFinite && $0.x.isFinite && $0.y.isFinite }
        for sample in samples where sample.clicked {
            let time = sample.time - request.trimOffset
            guard time >= lastEnd + 0.5, time < request.duration - 0.6, !map.isRemoved(takeTime: time) else { continue }
            let end = min(request.duration, time + 3)
            func position(_ sample: RecordingCursorSample) -> CGPoint {
                CGPoint(x: min(1, max(-1, (sample.x - 0.5) * 2 / max(0.01, amount))),
                        y: min(1, max(-1, (sample.y - 0.5) * 2 / max(0.01, amount))))
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

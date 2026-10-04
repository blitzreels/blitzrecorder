import SwiftUI
import XCTest
@testable import BlitzRecorderApp

@MainActor
final class RecordingHUDTests: XCTestCase {
    func testFreeDropPositionSurvivesResizingAndNearEdgePlacement() {
        for screen in [CGRect(x: 0, y: 0, width: 1440, height: 900),
                       CGRect(x: -1920, y: 300, width: 1920, height: 1080)] {
            for offset in [CGPoint(x: 2, y: 4), CGPoint(x: 500, y: 400), CGPoint(x: 620, y: 850)] {
                let origin = CGPoint(x: screen.minX + offset.x, y: screen.minY + offset.y)
                let panel = CGRect(origin: origin, size: CGSize(width: 220, height: 40))
                let position = RecordingHUDAnchor.normalizedTopLeft(.init(panelFrame: panel, visibleFrame: screen))
                XCTAssertEqual(RecordingHUDAnchor.freeOrigin(.init(
                    topLeft: position, size: panel.size, visibleFrame: screen, margin: 0)), origin)
            }
            let position = RecordingHUDAnchor.normalizedTopLeft(.init(
                panelFrame: CGRect(x: screen.minX + 500, y: screen.minY + 400, width: 340, height: 300),
                visibleFrame: screen))
            XCTAssertEqual(RecordingHUDAnchor.freeOrigin(.init(
                topLeft: position, size: CGSize(width: 220, height: 40), visibleFrame: screen, margin: 0)),
                CGPoint(x: screen.minX + 500, y: screen.minY + 660))
        }
    }

    func testStartingDragKeepsExpandedBarStable() {
        let model = RecordingHUDModel()
        model.isHovering = true
        XCTAssertTrue(model.isExpanded)
        model.isDragging = true
        XCTAssertTrue(model.isExpanded, "Starting a drag must not collapse the bar beneath the pointer")
        model.isHovering = false
        XCTAssertTrue(model.isExpanded, "Moving beyond the old bounds must not collapse the drag surface")
        model.isDragging = false
        XCTAssertFalse(model.isExpanded)
    }

    func testSettingsAspectNeverOverridesLiveFrames() {
        let stage = PreviewStageView()
        stage.applyLiveFrameAspectRatio(1.8156)
        stage.applySettingsAspectRatio(2.0833)
        XCTAssertEqual(stage.screenSourceAspectRatio, 1.8156, accuracy: 0.0001)
    }

    func testRendersEveryState() throws {
        let suiteName = "BlitzRecorder.RecordingHUDTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let coordinator = RecorderCoordinator(accessController: AccessController(defaults: defaults), defaults: defaults)
        let vm = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        vm.state = .recording
        vm.settings.enabledSources = [.screen, .microphone]
        vm.settings.screenSourceBinding = ScreenSourceBinding(kind: .window, displayID: nil, bundleIdentifier: "com.google.Chrome",
            applicationName: "Google Chrome", processID: 1, windowID: 1, windowTitle: "LinkedIn")
        for index in 0..<32 { vm.micLevels.append(Float(abs(sin(Double(index) / 2))) * 0.9) }
        let notion = ScreenSourceBinding(kind: .window, displayID: nil, bundleIdentifier: "com.openai.codex",
            applicationName: "ChatGPT", processID: nil, windowID: 2, windowTitle: "Plan")
        let states: [(String, Bool, ScreenSourceBinding?, RecordingHUDAnchor)] = [
            ("compact", false, nil, .topCenter), ("expanded", true, nil, .topCenter),
            ("prompt", false, notion, .topCenter), ("bottom", true, nil, .bottomRight),
            ("missing", false, nil, .topCenter)
        ]
        for (name, expanded, suggestion, anchor) in states {
            let model = RecordingHUDModel()
            model.anchor = anchor
            model.isHovering = expanded
            vm.suggestedScreenSource = suggestion
            vm.unavailableScreenSource = name == "missing" ? vm.settings.screenSourceBinding : nil
            let view = RecordingHUDView(vm: vm, model: model, actions: .init(resize: { _ in }, dragChanged: {}, dragEnded: {}))
                .padding(24)
                .background(Color(red: 0.86, green: 0.88, blue: 0.92))
            let host = NSHostingView(rootView: view)
            host.appearance = NSAppearance(named: .darkAqua)
            host.setFrameSize(host.fittingSize)
            host.layoutSubtreeIfNeeded()
            XCTAssertLessThan(host.fittingSize.width, 420)
            guard let directory = ProcessInfo.processInfo.environment["BLITZRECORDER_SILENCE_UI_PROOF"] else { continue }
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent("hud-\(name).png"))
        }
        UserDefaults.standard.removeObject(forKey: "recordingHUD.anchor")
    }
}

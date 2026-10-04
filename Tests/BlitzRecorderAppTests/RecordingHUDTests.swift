import SwiftUI
import XCTest
@testable import BlitzRecorderApp

@MainActor
final class RecordingHUDTests: XCTestCase {
    func testSnapsOnlyNearAnchorsAndOtherwisePlacesFreely() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        XCTAssertEqual(RecordingHUDAnchor.snapTarget(.init(
            panelFrame: CGRect(x: 610, y: 840, width: 220, height: 40), visibleFrame: screen, threshold: 64)), .topCenter)
        XCTAssertEqual(RecordingHUDAnchor.snapTarget(.init(
            panelFrame: CGRect(x: 1200, y: 20, width: 220, height: 40), visibleFrame: screen, threshold: 64)), .bottomRight)
        let middle = RecordingHUDAnchor.SnapRequest(
            panelFrame: CGRect(x: 500, y: 400, width: 220, height: 40), visibleFrame: screen, threshold: 64)
        XCTAssertNil(RecordingHUDAnchor.snapTarget(middle))
        let topLeft = RecordingHUDAnchor.normalizedTopLeft(middle)
        XCTAssertEqual(RecordingHUDAnchor.freeOrigin(.init(
            topLeft: topLeft, size: CGSize(width: 220, height: 40), visibleFrame: screen, margin: 10)), CGPoint(x: 500, y: 400))
        XCTAssertEqual(RecordingHUDAnchor.freeOrigin(.init(
            topLeft: CGPoint(x: 0.9, y: 0.05), size: CGSize(width: 340, height: 300), visibleFrame: screen, margin: 10)),
            CGPoint(x: 1090, y: 10))
        XCTAssertEqual(RecordingHUDAnchor.topCenter.origin(.init(
            size: CGSize(width: 340, height: 300), visibleFrame: screen, margin: 10)), CGPoint(x: 550, y: 590))
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
        let notion = ScreenSourceBinding(kind: .window, displayID: nil, bundleIdentifier: "notion.id",
            applicationName: "Notion", processID: 2, windowID: 2, windowTitle: "Plan")
        let states: [(String, Bool, ScreenSourceBinding?, RecordingHUDAnchor)] = [
            ("compact", false, nil, .topCenter), ("expanded", true, nil, .topCenter),
            ("prompt", false, notion, .topCenter), ("bottom", true, nil, .bottomRight)
        ]
        for (name, expanded, suggestion, anchor) in states {
            let model = RecordingHUDModel()
            model.anchor = anchor
            model.isHovering = expanded
            vm.suggestedScreenSource = suggestion
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

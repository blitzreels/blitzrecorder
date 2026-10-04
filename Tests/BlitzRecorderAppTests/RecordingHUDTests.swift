import SwiftUI
import XCTest
@testable import BlitzRecorderApp

@MainActor
final class RecordingHUDTests: XCTestCase {
    func testSnapsToNearestAnchorAndKeepsEdgeFixed() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        XCTAssertEqual(RecordingHUDAnchor.nearest(.init(center: CGPoint(x: 700, y: 860), visibleFrame: screen)), .topCenter)
        XCTAssertEqual(RecordingHUDAnchor.nearest(.init(center: CGPoint(x: 1300, y: 80), visibleFrame: screen)), .bottomRight)
        let size = CGSize(width: 340, height: 300)
        XCTAssertEqual(RecordingHUDAnchor.topCenter.origin(.init(size: size, visibleFrame: screen, margin: 10)),
                       CGPoint(x: 550, y: 590))
        XCTAssertEqual(RecordingHUDAnchor.bottomLeft.origin(.init(size: size, visibleFrame: screen, margin: 10)),
                       CGPoint(x: 10, y: 10))
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

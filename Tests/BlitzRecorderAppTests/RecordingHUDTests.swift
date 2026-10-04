import SwiftUI
import XCTest
@testable import BlitzRecorderApp

@MainActor
final class RecordingHUDTests: XCTestCase {
    func testHUDRendersCompactAndWithSwitchPrompt() throws {
        let suiteName = "BlitzRecorder.RecordingHUDTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let coordinator = RecorderCoordinator(accessController: AccessController(defaults: defaults), defaults: defaults)
        let vm = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        vm.state = .recording
        vm.settings.enabledSources = [.screen, .microphone]
        vm.settings.screenSourceBinding = ScreenSourceBinding(kind: .window, displayID: nil, bundleIdentifier: "com.google.Chrome",
            applicationName: "Google Chrome", processID: 1, windowID: 1, windowTitle: "LinkedIn")
        for index in 0..<32 { vm.micLevels.append(Float(abs(sin(Double(index) / 3))) * 0.8) }
        vm.settings.enabledSources = [.screen, .microphone, .systemAudio]
        for index in 0..<32 { vm.sysLevels.append(Float(abs(cos(Double(index) / 4))) * 0.5) }
        let notion = ScreenSourceBinding(kind: .window, displayID: nil, bundleIdentifier: "notion.id",
            applicationName: "Notion", processID: 2, windowID: 2, windowTitle: "Plan")
        for (name, suggestion, collapsed) in [("expanded", nil, false), ("prompt", notion, false), ("collapsed", nil, true)] {
            UserDefaults.standard.set(collapsed, forKey: "recordingHUD.collapsed")
            vm.suggestedScreenSource = suggestion
            let host = NSHostingView(rootView: RecordingHUDView(vm: vm).padding(20).background(Color(white: 0.3)))
            host.appearance = NSAppearance(named: .darkAqua)
            host.setFrameSize(host.fittingSize)
            host.layoutSubtreeIfNeeded()
            XCTAssertLessThan(host.fittingSize.width, 700)
            UserDefaults.standard.removeObject(forKey: "recordingHUD.collapsed")
            guard let directory = ProcessInfo.processInfo.environment["BLITZRECORDER_SILENCE_UI_PROOF"] else { continue }
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent("hud-\(name).png"))
        }
    }
}

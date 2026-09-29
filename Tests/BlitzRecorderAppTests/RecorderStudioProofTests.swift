import AppKit
import SwiftUI
import XCTest
@testable import BlitzRecorderApp

final class RecorderStudioProofTests: XCTestCase {
    @MainActor
    func testRecorderStudioRenders() async throws {
        guard let output = ProcessInfo.processInfo.environment["BLITZRECORDER_EXPORT_UI_PROOF"] else {
            throw XCTSkip("Provide a proof output directory.")
        }
        let suite = "RecorderStudioProof.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = RecorderCoordinator(accessController: AccessController(defaults: defaults), defaults: defaults)
        let vm = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        defer { vm.prepareForWindowClose() }
        let server = BlitzRecorderMCPServer(coordinator: coordinator)
        let host = NSHostingView(rootView: MainView(configuration: .init(viewModel: vm, mcpServer: server))
            .environmentObject(AppUpdateController()).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }

        func snap(_ name: String) async throws {
            try await Task.sleep(for: .seconds(1))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
                to: URL(fileURLWithPath: output).appendingPathComponent("\(name).png"))
        }

        vm.dismissFirstRunOnboarding()
        vm.showRecorder()
        vm.setLayout(.vertical)
        vm.selectSource(.camera)
        try await snap("studio-vertical-camera")
        vm.selectSource(.screen)
        try await snap("studio-vertical-screen")
        vm.selectSource(.microphone)
        try await snap("studio-vertical-audio")
        vm.selectBackgroundLayer()
        try await snap("studio-vertical-background")
        let safeZones = UserDefaults.standard.object(forKey: ShortFormSafeZone.preferenceKey)
        UserDefaults.standard.set(true, forKey: ShortFormSafeZone.preferenceKey)
        vm.selectSource(.camera)
        try await snap("studio-vertical-safe-zones")
        UserDefaults.standard.set(safeZones, forKey: ShortFormSafeZone.preferenceKey)
        vm.countdownRemaining = 3
        try await snap("studio-countdown")
        vm.countdownRemaining = nil
        vm.setScenePreset(.cameraInset)
        try await snap("studio-vertical-inset-camera")
        vm.setCameraInsetShape(.circle)
        try await snap("studio-vertical-round-camera")
        vm.setLayout(.horizontal)
        vm.selectSource(.camera)
        try await snap("studio-landscape-camera")
        window.setContentSize(CGSize(width: 1120, height: 760))
        try await snap("studio-landscape-min")
    }
}

import AppKit
import SwiftUI
import XCTest
@testable import BlitzRecorderApp

final class ProjectsProofTests: XCTestCase {
    @MainActor
    func testProjectsLibraryAndDetailTabsRender() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let library = environment["BLITZRECORDER_PROOF_LIBRARY"],
              let output = environment["BLITZRECORDER_EXPORT_UI_PROOF"] else {
            throw XCTSkip("Provide an isolated library copy and a proof output directory.")
        }
        let suite = "ProjectsProof.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = RecordingSettings()
        settings.outputDirectory = URL(fileURLWithPath: library)
        RecordingSettingsStore.save(settings, defaults: defaults)
        let coordinator = RecorderCoordinator(accessController: AccessController(defaults: defaults), defaults: defaults)
        let vm = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        let automatic = vm.transcriptionController.isAutomaticEnabled
        vm.transcriptionController.isAutomaticEnabled = false
        defer { vm.transcriptionController.isAutomaticEnabled = automatic; vm.prepareForWindowClose() }
        let server = BlitzRecorderMCPServer(coordinator: coordinator)
        let host = NSHostingView(rootView: MainView(configuration: .init(viewModel: vm, mcpServer: server))
            .environmentObject(AppUpdateController()).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }

        func snap(_ name: String, wait: Duration) async throws {
            try await Task.sleep(for: wait)
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
                to: URL(fileURLWithPath: output).appendingPathComponent("\(name).png"))
        }

        vm.dismissFirstRunOnboarding()
        vm.showProjects()
        try await snap("projects-list", wait: .seconds(3))
        if let second = vm.recentProjects.dropFirst().first {
            vm.projectLibraryNavigation.selectedProjectIDs = [second.id]
            try await snap("projects-second", wait: .seconds(3))
        }
        vm.showRecorder()
        try await snap("recorder", wait: .seconds(2))
        for pane in [SettingsPane.recording, .accounts, .agents] {
            vm.showSettings(pane)
            try await snap("settings-\(pane.title.lowercased())", wait: .seconds(1))
            if pane == .recording {
                window.setContentSize(CGSize(width: 1440, height: 1900))
                try await snap("settings-recording-full", wait: .seconds(1))
                window.setContentSize(CGSize(width: 1440, height: 900))
            }
        }
    }
}

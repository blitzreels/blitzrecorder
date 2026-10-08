import AppKit
import SwiftUI
import XCTest
@testable import BlitzRecorderApp

final class AppShellProofTests: XCTestCase {
    @MainActor
    func testSidebarEditorToastAndUpdateRender() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let library = environment["BLITZRECORDER_PROOF_LIBRARY"],
              let output = environment["BLITZRECORDER_EXPORT_UI_PROOF"] else {
            throw XCTSkip("Provide an isolated library copy and a proof output directory.")
        }
        let suite = "AppShellProof.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = RecordingSettings()
        settings.outputDirectory = URL(fileURLWithPath: library)
        RecordingSettingsStore.save(settings, defaults: defaults)
        let sidebarHidden = UserDefaults.standard.object(forKey: "appSidebarHidden")
        UserDefaults.standard.set(false, forKey: "appSidebarHidden")
        defer { UserDefaults.standard.set(sidebarHidden, forKey: "appSidebarHidden") }
        let coordinator = RecorderCoordinator(accessController: AccessController(defaults: defaults), defaults: defaults)
        let vm = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        let automatic = vm.transcriptionController.isAutomaticEnabled
        vm.transcriptionController.isAutomaticEnabled = false
        defer { vm.transcriptionController.isAutomaticEnabled = automatic; vm.prepareForWindowClose() }
        let updates = AppUpdateController()
        let server = BlitzRecorderMCPServer(coordinator: coordinator)
        let host = NSHostingView(rootView: MainView(configuration: .init(viewModel: vm, mcpServer: server))
            .environmentObject(updates).preferredColorScheme(.dark))
        let width = CGFloat(Double(environment["BLITZRECORDER_PROOF_WIDTH"] ?? "") ?? 1440)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: 900),
            styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        MainWindowChrome.configure(window)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }

        func snap(_ name: String, wait: Duration) async throws {
            try await Task.sleep(for: wait)
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
                to: URL(fileURLWithPath: output).appendingPathComponent("shell-\(name).png"))
        }

        vm.dismissFirstRunOnboarding()
        vm.showSidebarDestination(.recordings)
        try await snap("recordings", wait: .seconds(3))

        let index = ProjectFolderIndex(.init(projects: vm.recentProjects, pins: ProjectFolderStore.shared.pins))
        if let folder = ProjectFolderTree.roots(.init(projects: vm.recentProjects, index: index, includesEmpty: true)).first {
            vm.showSidebarDestination(.folder(.init(path: folder.path, module: nil)))
            try await snap("folder", wait: .seconds(2))
            if let module = folder.modules.first {
                vm.showSidebarDestination(.folder(.init(path: folder.path, module: module.id)))
                try await snap("module", wait: .seconds(2))
            }
        }

        vm.showSidebarDestination(.shared)
        try await snap("shared", wait: .seconds(2))

        vm.showSettings(.uiKit)
        try await snap("settings-ui-kit", wait: .seconds(1))
        vm.dismissSettings()

        if let project = vm.recentProjects.first {
            vm.openProject(project)
            try await snap("editor", wait: .seconds(3))
            vm.lastExportSucceededURL = URL(fileURLWithPath: "/tmp/trailer-landscape.mov")
            try await snap("editor-export-toast", wait: .milliseconds(600))
            vm.lastExportSucceededURL = nil
        }

        updates.prepareInstallation(.init(version: "0.35.0", install: {}))
        try await snap("editor-update-ready", wait: .seconds(1))

        UserDefaults.standard.set(true, forKey: "appSidebarHidden")
        try await snap("editor-sidebar-hidden", wait: .seconds(1))
        UserDefaults.standard.set(false, forKey: "appSidebarHidden")

        vm.showSidebarDestination(.record)
        try await snap("record", wait: .seconds(2))
        vm.applyState(.recording)
        try await snap("record-live", wait: .seconds(1))
        vm.applyState(.idle)
    }
}

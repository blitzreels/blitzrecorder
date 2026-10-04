import AppKit
import SwiftUI
import XCTest
@testable import BlitzRecorderApp

final class EditorPaneProofTests: XCTestCase {
    @MainActor
    func testEveryEditorToolRendersOnTheSharedPane() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let take = environment["BLITZRECORDER_EDITOR_PROOF_TAKE"],
              let output = environment["BLITZRECORDER_EXPORT_UI_PROOF"] else {
            throw XCTSkip("Provide an isolated take copy and a proof output directory.")
        }
        let takeURL = URL(fileURLWithPath: take)
        let project = try TakeFileStore().loadRecordingProject(
            at: takeURL.appendingPathComponent("project.blitzrecorder.json"))
        let suite = "EditorPaneProof.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = RecorderCoordinator(accessController: AccessController(defaults: defaults), defaults: defaults)
        let vm = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        let automatic = vm.transcriptionController.isAutomaticEnabled
        vm.transcriptionController.isAutomaticEnabled = false
        defer { vm.transcriptionController.isAutomaticEnabled = automatic; vm.prepareForWindowClose() }
        vm.lastExportedSourceTakeURL = takeURL
        vm.refreshLastExportedProject()
        vm.studioMode = .edit
        let tabs: [EditorInspectorTab] = [.layout, .silence, .captions, .text, .zoom, .privacy, .audio]
        for (index, tab) in (tabs + [.silence, .silence]).enumerated() {
            if index == tabs.count + 1 { vm.lastExportSucceededURL = nil }
            if index == tabs.count {
                vm.lastExportSucceededURL = URL(fileURLWithPath: "/Volumes/Exports/Maîtriser l'IA pour le business.mp4")
            }
            let host = NSHostingView(rootView: EditorView(vm: vm, loadedProjectID: project.id, inspectorTab: tab)
                .environmentObject(AppUpdateController()).preferredColorScheme(.dark))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: index == tabs.count + 1 ? 1920 : 1440, height: 900),
                styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.contentView = host
            window.orderFront(nil)
            try await Task.sleep(for: .seconds(tab == tabs.first ? 4 : 2))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
                to: URL(fileURLWithPath: output).appendingPathComponent(
                    index == tabs.count + 1 ? "editor-wide.png"
                        : index == tabs.count ? "editor-notice.png" : "editor-\(tab.rawValue.lowercased()).png"))
            window.orderOut(nil)
            window.contentView = nil
        }
        vm.lastExportSucceededURL = nil
    }
}

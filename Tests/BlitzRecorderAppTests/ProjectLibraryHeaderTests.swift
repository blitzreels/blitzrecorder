import AppKit
import SwiftUI
import Vision
import XCTest
@testable import BlitzRecorderApp

@MainActor
final class ProjectLibraryHeaderTests: XCTestCase {
    func testLoadingHeaderRemainsReadableAtNarrowDetailWidths() async throws {
        let suite = "ProjectLibraryHeaderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let vm = RecorderViewModel(coordinator: RecorderCoordinator(
            accessController: AccessController(defaults: defaults), defaults: defaults), previewStage: PreviewStageView())
        defer { vm.prepareForWindowClose() }
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-08T19:31:00Z"))
        let project = RecordingProjectHistory.Entry(id: UUID(), title: "Recording at 21:31",
            projectPath: "/tmp/header-proof/project.blitzrecorder.json", takeDirectoryPath: "/tmp/header-proof",
            finalVideoPath: nil, createdAt: date, updatedAt: date, exports: [])
        ProjectLibraryMetadataStore.shared.store([(project, .init(thumbnail: nil, durationSeconds: 277,
            sourceSummary: "Screen + Camera + 2 audio tracks", sizeBytes: 590_000_000,
            videoQuality: nil, sourceRoles: ["screen", "camera", "microphone", "systemAudio"]))])
        vm.recentProjects = [project]
        vm.projectLibraryNavigation.selectedProjectIDs = [project.id]
        vm.transcriptionController.jobStatuses[project.projectPath] = .loadingModels
        for width in [520.0, 640.0, 1000.0] {
            let host = NSHostingView(rootView: ProjectLibraryView(vm: vm).projectDetail
                .frame(width: width, height: 600).preferredColorScheme(.dark))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: 600),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let image = try XCTUnwrap(bitmap.cgImage)
            if let output = ProcessInfo.processInfo.environment["BLITZ_HEADER_PROOF"] {
                try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
                    to: URL(fileURLWithPath: output).appendingPathComponent("header-\(Int(width)).png"))
            }
            let headerLines = try RenderedText.observations(.init(image: image, customWords: []))
                .filter { $0.boundingBox.midY > 0.65 }
                .compactMap { $0.topCandidates(1).first?.string }
            XCTAssertTrue(headerLines.contains { $0.contains("Loading speech model") },
                "Header at \(Int(width)) points splits its status: \(headerLines)")
            window.contentView = nil
        }
    }
}

import AppKit
import SwiftUI
import Vision
import XCTest
@testable import BlitzRecorderApp

@MainActor
final class ResponsivePagesTests: XCTestCase {
    func testPageHeadersAndActionsStayReadableAtNarrowAndWideWidths() async throws {
        let suite = "ResponsivePagesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = RecorderCoordinator(accessController: AccessController(defaults: defaults), defaults: defaults)
        let vm = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        defer { vm.prepareForWindowClose() }
        let server = BlitzRecorderMCPServer(coordinator: coordinator)
        let pages: [(String, AnyView, [String])] = [
            ("recording", AnyView(RecordingSettingsPage(vm: vm)), ["Recording", "Change Folder", "Audio quality"]),
            ("speakers", AnyView(SpeakersSettingsPage(projects: [], openRecording: { _ in })), ["Speakers", "Detect voices"]),
            ("iphone", AnyView(RemoteCameraPage(vm: vm)), ["Phone Camera", "Get iPhone app", "Search again"]),
            ("permissions", AnyView(PermissionsPage(vm: vm)), ["Permissions", "Recheck"]),
            ("accounts", AnyView(AccountsSettingsPage(vm: vm)), ["Accounts", "BlitzRecorder", "BlitzReels"]),
            ("integrations", AnyView(AgentsSettingsPage(mcpServer: server)), ["Integrations", "Test server", "Install Claude extension"]),
            ("about", AnyView(AboutSettingsPage()), ["About", "Release Notes", "View on GitHub"])
        ]
        for width in [480.0, 760.0] {
            for (name, page, expected) in pages {
                let lines = try await render(.init(name: "\(name)-\(Int(width))", view: page, width: width, height: 2200))
                for phrase in expected {
                    XCTAssertTrue(lines.contains { $0.localizedCaseInsensitiveContains(phrase) },
                                  "\(name) at \(width) clips or splits \(phrase): \(lines)")
                }
            }
        }
    }

    func testLongDescriptionAndControlsReflowWithoutSplittingWords() async throws {
        let row = BlitzAdaptiveRow() {
            SettingsRowLabel(.init(title: "Local speech model", detail: "Loading speech model before transcription begins."))
            SettingsStatusBadge(configuration: .init(title: "Downloading", tone: .muted))
            Button("Try again") {}.blitzButton(.secondary)
        }
        .padding(20)
        for width in [300.0, 480.0, 760.0] {
            let lines = try await render(.init(name: "row-\(Int(width))", view: AnyView(row), width: width, height: 220))
            for phrase in ["Local speech model", "Loading speech model", "Downloading", "Try again"] {
                XCTAssertTrue(lines.contains { $0.contains(phrase) }, "Row at \(width) clips \(phrase): \(lines)")
            }
        }
    }

    private struct RenderRequest {
        let name: String
        let view: AnyView
        let width: CGFloat
        let height: CGFloat
    }

    private func render(_ request: RenderRequest) async throws -> [String] {
        let host = NSHostingView(rootView: request.view
            .environmentObject(AppUpdateController())
            .frame(width: request.width, height: request.height, alignment: .topLeading)
            .preferredColorScheme(.dark))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: request.width, height: request.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        if let output = ProcessInfo.processInfo.environment["BLITZ_RESPONSIVE_PROOF"] {
            try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
                to: URL(fileURLWithPath: output).appendingPathComponent("\(request.name).png"))
        }
        let image = try XCTUnwrap(bitmap.cgImage)
        var lines: [String] = []
        for y in stride(from: 0, to: image.height, by: 700) {
            let crop = try XCTUnwrap(image.cropping(to: CGRect(x: 0, y: y, width: image.width,
                                                              height: min(800, image.height - y))))
            lines += try RenderedText.observations(.init(image: crop, customWords: ["iPhone", "BlitzRecorder", "BlitzReels"]))
                .compactMap { $0.topCandidates(1).first?.string }
        }
        return lines
    }
}

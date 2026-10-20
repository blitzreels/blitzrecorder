import Foundation
import XCTest
@testable import BlitzRecorderApp

final class MCPClientSetupTests: XCTestCase {
    func testProviderSetupKeepsOtherServersAndSettingsAndIsIdempotent() async throws {
        for provider in [MCPClientProvider.claudeCode, .cursor, .windsurf, .gemini] {
            let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: home) }
            let path = try XCTUnwrap(provider.relativeConfigurationPath)
            let file = home.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let original = Data(#"{"preference":true,"mcpServers":{"existing":{"command":"keep-me","env":{"TEST":"unchanged"}}}}"#.utf8)
            try original.write(to: file)
            let request = MCPClientSetup.Request(provider: provider, home: home)
            try MCPClientSetup.mergeConfiguration(.init(request: request, mode: .add))
            let status = await MCPClientSetup.status(request)
            XCTAssertEqual(status, .configured)
            let first = try Data(contentsOf: file)
            let document = try XCTUnwrap(JSONSerialization.jsonObject(with: first) as? [String: Any])
            XCTAssertEqual(document["preference"] as? Bool, true)
            let servers = try XCTUnwrap(document["mcpServers"] as? [String: Any])
            XCTAssertEqual((servers["existing"] as? [String: Any])?["command"] as? String, "keep-me")
            XCTAssertEqual(servers["blitzrecorder"] as? [String: String], provider.serverConfiguration)
            try MCPClientSetup.mergeConfiguration(.init(request: request, mode: .add))
            XCTAssertEqual(try Data(contentsOf: file), first)
            let backups = try FileManager.default.contentsOfDirectory(at: file.deletingLastPathComponent(), includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "backup" }
            XCTAssertEqual(backups.count, 1)
            XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), original)
        }
    }

    func testConflictingAndMalformedConfigurationIsNeverOverwritten() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appendingPathComponent(".cursor/mcp.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        for text in [
            #"{"mcpServers":{"blitzrecorder":{"url":"http://127.0.0.1:9999/other"}}}"#,
            #"{"mcpServers":[]}"#,
            #"{"mcpServers": {"#,
            "[]"
        ] {
            let original = Data(text.utf8)
            try original.write(to: file)
            let request = MCPClientSetup.Request(provider: .cursor, home: home)
            let status = await MCPClientSetup.status(request)
            XCTAssertNotEqual(status, .missing)
            XCTAssertNotEqual(status, .configured)
            XCTAssertThrowsError(try MCPClientSetup.mergeConfiguration(.init(request: request, mode: .add)))
            XCTAssertEqual(try Data(contentsOf: file), original)
        }
    }

    func testNewConfigurationCreatesOnlyTheRequestedProviderEntry() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let request = MCPClientSetup.Request(provider: .cursor, home: home)
        await XCTAssertStatusMissing(request)
        try await MCPClientSetup.install(request)
        let status = await MCPClientSetup.status(request)
        XCTAssertEqual(status, .configured)
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude.json").path))
    }

    func testCommandsUseUserScopeAndCloudClientsAreNotOfferedLocalInstallation() {
        XCTAssertTrue(MCPClientProvider.claudeCode.setupCommand?.contains("--scope user") == true)
        XCTAssertTrue(MCPClientProvider.gemini.setupCommand?.contains("--scope user") == true)
        XCTAssertFalse(MCPClientProvider.cloud.canInstallConfiguration)
        XCTAssertNil(MCPClientProvider.cloud.relativeConfigurationPath)
        XCTAssertTrue(MCPClientProvider.cloud.detail.contains("cannot reach"))
        XCTAssertEqual(MCPClientProvider.vscode.serverKey, "servers")
    }

    func testDesktopBundleContainsTheManifestAndBridgeAtItsRoot() async throws {
        let file = try await MCPDesktopExtension.createBundle()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z1", file.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let contents = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertTrue(contents.components(separatedBy: .newlines).contains("manifest.json"))
        XCTAssertTrue(contents.components(separatedBy: .newlines).contains("bridge.cjs"))
    }

    private func XCTAssertStatusMissing(_ request: MCPClientSetup.Request) async {
        let status = await MCPClientSetup.status(request)
        XCTAssertEqual(status, .missing)
    }
}

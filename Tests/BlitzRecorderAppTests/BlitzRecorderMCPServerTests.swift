import Foundation
import MCP
import XCTest
@testable import BlitzRecorderApp

final class BlitzRecorderMCPServerTests: XCTestCase {
    @MainActor
    func testEveryClientCanInitializeListAndCallTools() async throws {
        let suite = "MCPServer.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = RecorderCoordinator(accessController: AccessController(defaults: defaults), defaults: defaults)
        let server = BlitzRecorderMCPServer(coordinator: coordinator)

        for client in ["codex", "claude-code", "blitzrecorder-settings"] {
            let initialize = try await send(server, #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"\#(client)","version":"1"}}}"#)
            let info = try XCTUnwrap((initialize["result"] as? [String: Any])?["serverInfo"] as? [String: Any], "\(client): \(initialize)")
            XCTAssertEqual(info["name"] as? String, "blitzrecorder")
        }

        let list = try await send(server, #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        let tools = try XCTUnwrap((list["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.compactMap { $0["name"] as? String },
                       ["projects_list", "project_get", "project_transcript", "project_frame", "projects_export_as_is", "export_status"])

        let call = try await send(server, #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"projects_list","arguments":{"limit":1}}}"#)
        let result = try XCTUnwrap(call["result"] as? [String: Any], "\(call)")
        XCTAssertNotEqual(result["isError"] as? Bool, true)
    }

    @MainActor
    private func send(_ server: BlitzRecorderMCPServer, _ body: String) async throws -> [String: Any] {
        let response = await server.respond(to: HTTPRequest(method: "POST", headers: [
            "Content-Type": "application/json",
            "Accept": "application/json",
            "Origin": "http://localhost:\(BlitzRecorderMCPServer.port)",
            "MCP-Protocol-Version": "2025-06-18",
        ], body: Data(body.utf8), path: BlitzRecorderMCPServer.endpoint))
        XCTAssertEqual(response.statusCode, 200)
        let data = try XCTUnwrap(response.bodyData)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @MainActor
    func testFrameToolRejectsInvalidArguments() async throws {
        let suite = "MCPFrameArguments.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = RecorderCoordinator(accessController: AccessController(defaults: defaults), defaults: defaults)
        let server = BlitzRecorderMCPServer(coordinator: coordinator)
        let id = UUID().uuidString
        for arguments in [
            #"{"projectId":"\#(id)","source":"microphone","timeSeconds":0}"#,
            #"{"projectId":"\#(id)","source":"screen","timeSeconds":-1}"#,
            #"{"projectId":"\#(id)","source":"screen","timeSeconds":"0"}"#,
            #"{"projectId":"\#(id)","source":"screen"}"#
        ] {
            let response = try await send(server, #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"project_frame","arguments":\#(arguments)}}"#)
            let result = try XCTUnwrap(response["result"] as? [String: Any])
            XCTAssertEqual(result["isError"] as? Bool, true)
        }
    }
}

import Foundation

struct MCPConnectionVerification: Equatable {
    let date: Date
    let toolCount: Int
}

struct MCPClientHandshake: Equatable {
    let name: String
    let date: Date
}

enum MCPConnectionProbe {
    struct Configuration {
        let endpoint: URL
        let session: URLSession
    }

    private struct Request {
        let configuration: Configuration
        let method: String
        let parameters: [String: Any]
        let id: Int?
        let protocolVersion: String
    }

    static func test(_ configuration: Configuration) async throws -> Int {
        let initialized = try await send(.init(
            configuration: configuration, method: "initialize", parameters: [
                "protocolVersion": "2025-11-25", "capabilities": [:],
                "clientInfo": ["name": "blitzrecorder-settings", "version": "1.0"]
            ], id: 1, protocolVersion: "2025-11-25"
        ))
        guard let info = initialized["serverInfo"] as? [String: Any], info["name"] as? String == "blitzrecorder",
              let version = initialized["protocolVersion"] as? String else {
            throw MCPClientSetup.SetupError.message("Another service answered on BlitzRecorder's port. Quit other copies of the app and try again.")
        }
        _ = try await send(.init(configuration: configuration, method: "notifications/initialized", parameters: [:], id: nil, protocolVersion: version))
        let listed = try await send(.init(configuration: configuration, method: "tools/list", parameters: [:], id: 2, protocolVersion: version))
        guard let tools = listed["tools"] as? [[String: Any]],
              Set(tools.compactMap { $0["name"] as? String }).isSuperset(of: [
                "projects_list", "project_get", "project_transcript", "project_frame", "projects_export_as_is", "export_status"
              ]) else {
            throw MCPClientSetup.SetupError.message("The server connected, but its recording tools could not be discovered.")
        }
        let result = try await send(.init(
            configuration: configuration, method: "tools/call",
            parameters: ["name": "projects_list", "arguments": ["limit": 1]], id: 3, protocolVersion: version
        ))
        guard result["isError"] as? Bool != true, result["content"] is [[String: Any]] else {
            throw MCPClientSetup.SetupError.message("The tools were discovered, but reading the recording library failed.")
        }
        return tools.count
    }

    private static func send(_ probe: Request) async throws -> [String: Any] {
        var request = URLRequest(url: probe.configuration.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(probe.protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        var body: [String: Any] = ["jsonrpc": "2.0", "method": probe.method, "params": probe.parameters]
        if let id = probe.id { body["id"] = id }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await probe.configuration.session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw MCPClientSetup.SetupError.message("\(probe.method): no response from the local server.")
        }
        if probe.id == nil, response.statusCode == 202 { return [:] }
        guard response.statusCode == 200,
              let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              payload["error"] == nil, let result = payload["result"] as? [String: Any] else {
            throw MCPClientSetup.SetupError.message("\(probe.method) failed (HTTP \(response.statusCode)). Keep BlitzRecorder open and check local agent access.")
        }
        return result
    }
}

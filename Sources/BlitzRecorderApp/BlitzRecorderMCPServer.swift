import Foundation
import MCP
import Observation
import os

private let mcpLog = Logger(subsystem: "dev.blitzreels.blitzrecorder", category: "mcp")

enum BlitzRecorderMCPServerStatus: Equatable {
    case disabled
    case stopped
    case starting
    case running
    case failed(String)
}

enum BlitzRecorderMCPConnectionTestStatus: Equatable {
    case notRun
    case testing
    case succeeded(Date)
    case failed(String)
}

@Observable
@MainActor
final class BlitzRecorderMCPServer {
    nonisolated static let port = 18_473
    nonisolated static let endpoint = "/mcp"
    nonisolated static let workspaceEndpoint = "/webmcp"
    nonisolated static let endpointURL = URL(string: "http://127.0.0.1:\(port)\(endpoint)")!
    nonisolated static let workspaceURL = URL(
        string: "http://127.0.0.1:\(port)\(workspaceEndpoint)"
    )!
    nonisolated static let codexSetupCommand = "codex mcp add blitzrecorder --url \(endpointURL.absoluteString)"
    nonisolated static let agentPluginConfiguration = """
    {
      "$schema": "https://agent-plugins.org/schemas/1.0.0/mcp.schema.json",
      "mcpServers": {
        "blitzrecorder": {
          "type": "streamable-http",
          "url": "http://127.0.0.1:18473/mcp"
        }
      }
    }
    """

    private static let enabledDefaultsKey = "agents.mcpServer.enabled.v1"

    private let projectService: MCPProjectService
    private let defaults: UserDefaults
    private var server: Server?
    private var transport: StatelessHTTPServerTransport?
    private var httpServer: LoopbackMCPHTTPServer?
    private(set) var isEnabled: Bool
    private(set) var status: BlitzRecorderMCPServerStatus
    private(set) var connectionTestStatus = BlitzRecorderMCPConnectionTestStatus.notRun

    init(coordinator: RecorderCoordinator) {
        let defaults = UserDefaults.standard
        let isEnabled = defaults.object(forKey: Self.enabledDefaultsKey) as? Bool ?? true
        self.defaults = defaults
        projectService = MCPProjectService(coordinator: coordinator)
        self.isEnabled = isEnabled
        status = isEnabled ? .stopped : .disabled
    }

    func start() async {
        guard isEnabled else {
            status = .disabled
            return
        }
        guard server == nil else { return }
        status = .starting

        let pipeline = StandardValidationPipeline(validators: [
            OriginValidator.localhost(port: Self.port),
            AcceptHeaderValidator(mode: .jsonOnly),
            ContentTypeValidator(),
            ProtocolVersionValidator(),
        ])
        let transport = StatelessHTTPServerTransport(validationPipeline: pipeline)
        let server = Server(
            name: "blitzrecorder",
            version: "0.1.0",
            capabilities: .init(tools: .init(listChanged: false))
        )

        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: Self.tools)
        }
        await server.withMethodHandler(CallTool.self) { [weak projectService] parameters in
            guard let projectService else {
                return Self.errorResult("BlitzRecorder is unavailable.")
            }
            do {
                switch parameters.name {
                case "projects_list":
                    let request = try Self.projectListRequest(parameters.arguments)
                    return try await Self.result(projectService.listProjects(request))
                case "project_get":
                    let projectID = try Self.projectID(parameters.arguments)
                    return try await Self.result(projectService.projectDetails(projectID: projectID))
                case "project_transcript":
                    let projectID = try Self.projectID(parameters.arguments)
                    return try await Self.result(projectService.transcript(.init(projectID: projectID)))
                case "projects_export_as_is":
                    let request = try Self.exportStartRequest(parameters.arguments)
                    return try await Self.result(projectService.startExport(request))
                case "export_status":
                    let jobID = try Self.jobID(parameters.arguments)
                    return try await Self.result(projectService.exportStatus(jobID: jobID))
                default:
                    return Self.errorResult("Unknown BlitzRecorder tool: \(parameters.name).")
                }
            } catch {
                return Self.errorResult(error.localizedDescription)
            }
        }

        let httpServer = LoopbackMCPHTTPServer(.init(
            host: "127.0.0.1",
            port: Self.port,
            endpoint: Self.endpoint,
            workspaceEndpoint: Self.workspaceEndpoint,
            workspaceData: Self.workspaceData,
            transport: transport
        ))

        do {
            try await server.start(transport: transport)
            try await httpServer.start()
            guard isEnabled else {
                await httpServer.stop()
                await server.stop()
                status = .disabled
                return
            }
            self.server = server
            self.transport = transport
            self.httpServer = httpServer
            status = .running
            mcpLog.info("BlitzRecorder MCP listening on 127.0.0.1:\(Self.port)")
        } catch {
            await server.stop()
            status = .failed(error.localizedDescription)
            mcpLog.error("BlitzRecorder MCP failed to start: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() async {
        await httpServer?.stop()
        await server?.stop()
        httpServer = nil
        transport = nil
        server = nil
        status = isEnabled ? .stopped : .disabled
    }

    func setEnabled(_ enabled: Bool) async {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledDefaultsKey)
        connectionTestStatus = .notRun
        if enabled {
            await start()
        } else {
            await stop()
        }
    }

    func testConnection() async {
        connectionTestStatus = .testing
        do {
            try await BlitzRecorderMCPConnectionTester.test(Self.endpointURL)
            connectionTestStatus = .succeeded(Date())
        } catch {
            connectionTestStatus = .failed(error.localizedDescription)
        }
    }

    nonisolated private static let tools: [Tool] = [
        Tool(
            name: "projects_list",
            title: "List BlitzRecorder projects",
            description: "List local BlitzRecorder projects with transcript and export availability.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "query": .object([
                        "type": "string",
                        "description": "Optional case-insensitive title search.",
                    ]),
                    "recordedAfter": .object([
                        "type": "string",
                        "format": "date-time",
                        "description": "Include projects recorded at or after this ISO-8601 timestamp.",
                    ]),
                    "recordedBefore": .object([
                        "type": "string",
                        "format": "date-time",
                        "description": "Include projects recorded before this ISO-8601 timestamp.",
                    ]),
                    "hasTranscript": .object([
                        "type": "boolean",
                        "description": "Optionally filter by saved transcript availability.",
                    ]),
                    "limit": .object([
                        "type": "integer",
                        "minimum": 1,
                        "maximum": 200,
                        "default": 50,
                        "description": "Maximum projects to return.",
                    ]),
                    "offset": .object([
                        "type": "integer",
                        "minimum": 0,
                        "default": 0,
                        "description": "Number of matching projects to skip.",
                    ]),
                ]),
                "additionalProperties": false,
            ]),
            annotations: .init(
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        ),
        Tool(
            name: "project_get",
            title: "Inspect a BlitzRecorder project",
            description: "Inspect source readiness, saved export recipe, and prior exports for one project.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "projectId": .object([
                        "type": "string",
                        "description": "Project UUID returned by projects_list.",
                    ]),
                ]),
                "required": ["projectId"],
                "additionalProperties": false,
            ]),
            annotations: .init(
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        ),
        Tool(
            name: "project_transcript",
            title: "Inspect a project transcript",
            description: "Read the saved local transcript for one BlitzRecorder project.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "projectId": .object([
                        "type": "string",
                        "description": "Project UUID returned by projects_list.",
                    ]),
                ]),
                "required": ["projectId"],
                "additionalProperties": false,
            ]),
            annotations: .init(
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        ),
        Tool(
            name: "projects_export_as_is",
            title: "Export projects as MP4",
            description: "Queue unchanged BlitzRecorder projects for sequential MP4 export.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "projectIds": .object([
                        "type": "array",
                        "items": .object(["type": "string"]),
                        "minItems": 1,
                        "description": "Project UUIDs returned by projects_list.",
                    ]),
                    "outputDirectory": .object([
                        "type": "string",
                        "description": "Optional absolute output directory. It must be the configured export folder or one of its subfolders.",
                    ]),
                ]),
                "required": ["projectIds"],
                "additionalProperties": false,
            ]),
            annotations: .init(
                readOnlyHint: false,
                destructiveHint: false,
                idempotentHint: false,
                openWorldHint: false
            )
        ),
        Tool(
            name: "export_status",
            title: "Check export status",
            description: "Check progress and output paths for a BlitzRecorder MCP export job.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "jobId": .object([
                        "type": "string",
                        "description": "Export job UUID returned by projects_export_as_is.",
                    ]),
                ]),
                "required": ["jobId"],
                "additionalProperties": false,
            ]),
            annotations: .init(
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        ),
    ]

    nonisolated private static var workspaceData: Data {
        if let url = Bundle.main.url(
            forResource: "WebMCPWorkspace",
            withExtension: "html"
        ), let data = try? Data(contentsOf: url) {
            return data
        }
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(
            forResource: "WebMCPWorkspace",
            withExtension: "html"
        ), let data = try? Data(contentsOf: url) {
            return data
        }
        #endif
        return Data("BlitzRecorder WebMCP workspace is unavailable.".utf8)
    }

    private struct UUIDArgumentRequest {
        let key: String
        let arguments: [String: Value]?
    }

    private struct OptionalArgumentRequest {
        let key: String
        let arguments: [String: Value]?
    }

    nonisolated private static func projectListRequest(
        _ arguments: [String: Value]?
    ) throws -> MCPProjectListRequest {
        let query = try optionalString(.init(key: "query", arguments: arguments))
        let recordedAfter = try optionalDate(.init(key: "recordedAfter", arguments: arguments))
        let recordedBefore = try optionalDate(.init(key: "recordedBefore", arguments: arguments))
        if let recordedAfter, let recordedBefore, recordedAfter >= recordedBefore {
            throw MCPToolArgumentError.invalid("recordedAfter must be earlier than recordedBefore.")
        }
        let hasTranscript = try optionalBool(.init(key: "hasTranscript", arguments: arguments))
        let limit = try optionalInt(.init(key: "limit", arguments: arguments)) ?? 50
        let offset = try optionalInt(.init(key: "offset", arguments: arguments)) ?? 0
        guard (1...200).contains(limit) else {
            throw MCPToolArgumentError.invalid("limit must be between 1 and 200.")
        }
        guard offset >= 0 else {
            throw MCPToolArgumentError.invalid("offset must be zero or greater.")
        }
        return MCPProjectListRequest(
            query: query?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            recordedAfter: recordedAfter,
            recordedBefore: recordedBefore,
            hasTranscript: hasTranscript,
            limit: limit,
            offset: offset
        )
    }

    nonisolated private static func projectID(_ arguments: [String: Value]?) throws -> UUID {
        try uuid(.init(key: "projectId", arguments: arguments))
    }

    nonisolated private static func jobID(_ arguments: [String: Value]?) throws -> UUID {
        try uuid(.init(key: "jobId", arguments: arguments))
    }

    nonisolated private static func projectIDs(_ arguments: [String: Value]?) throws -> [UUID] {
        guard let values = arguments?["projectIds"]?.arrayValue, !values.isEmpty else {
            throw MCPToolArgumentError.invalid("projectIds must contain at least one project UUID.")
        }
        return try values.map { value in
            guard let rawValue = value.stringValue, let id = UUID(uuidString: rawValue) else {
                throw MCPToolArgumentError.invalid("projectIds contains an invalid UUID.")
            }
            return id
        }
    }

    nonisolated private static func exportStartRequest(
        _ arguments: [String: Value]?
    ) throws -> MCPExportStartRequest {
        let projectIDs = try projectIDs(arguments)
        let outputDirectoryPath = try optionalString(.init(
            key: "outputDirectory",
            arguments: arguments
        ))?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let outputDirectoryPath, !outputDirectoryPath.isEmpty else {
            return MCPExportStartRequest(projectIDs: projectIDs, outputDirectory: nil)
        }
        guard outputDirectoryPath.hasPrefix("/") else {
            throw MCPToolArgumentError.invalid("outputDirectory must be an absolute path.")
        }
        return MCPExportStartRequest(
            projectIDs: projectIDs,
            outputDirectory: URL(fileURLWithPath: outputDirectoryPath, isDirectory: true)
        )
    }

    nonisolated private static func uuid(_ request: UUIDArgumentRequest) throws -> UUID {
        guard let rawValue = request.arguments?[request.key]?.stringValue,
              let id = UUID(uuidString: rawValue) else {
            throw MCPToolArgumentError.invalid("\(request.key) must be a valid UUID.")
        }
        return id
    }

    nonisolated private static func optionalString(
        _ request: OptionalArgumentRequest
    ) throws -> String? {
        guard let value = request.arguments?[request.key] else { return nil }
        guard let string = value.stringValue else {
            throw MCPToolArgumentError.invalid("\(request.key) must be a string.")
        }
        return string
    }

    nonisolated private static func optionalBool(
        _ request: OptionalArgumentRequest
    ) throws -> Bool? {
        guard let value = request.arguments?[request.key] else { return nil }
        guard let bool = value.boolValue else {
            throw MCPToolArgumentError.invalid("\(request.key) must be a boolean.")
        }
        return bool
    }

    nonisolated private static func optionalInt(
        _ request: OptionalArgumentRequest
    ) throws -> Int? {
        guard let value = request.arguments?[request.key] else { return nil }
        guard let int = value.intValue else {
            throw MCPToolArgumentError.invalid("\(request.key) must be an integer.")
        }
        return int
    }

    nonisolated private static func optionalDate(
        _ request: OptionalArgumentRequest
    ) throws -> Date? {
        guard let rawValue = try optionalString(request) else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: rawValue) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: rawValue) else {
            throw MCPToolArgumentError.invalid("\(request.key) must be an ISO-8601 timestamp.")
        }
        return date
    }

    nonisolated private static func result<Output: Codable>(_ output: Output) throws -> CallTool.Result {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(output)
        let text = String(decoding: data, as: UTF8.self)
        let structuredContent = try JSONDecoder().decode(Value.self, from: data)
        return CallTool.Result(
            content: [.text(text: text, annotations: nil, _meta: nil)],
            structuredContent: Optional.some(structuredContent),
            isError: false
        )
    }

    nonisolated private static func errorResult(_ message: String) -> CallTool.Result {
        .init(
            content: [.text(text: message, annotations: nil, _meta: nil)],
            isError: true
        )
    }
}

private enum BlitzRecorderMCPConnectionTester {
    private struct Response: Decodable {
        struct Result: Decodable {
            struct ServerInfo: Decodable {
                let name: String
            }

            let serverInfo: ServerInfo
        }

        let result: Result?
    }

    static func test(_ endpoint: URL) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("http://localhost:\(BlitzRecorderMCPServer.port)", forHTTPHeaderField: "Origin")
        request.httpBody = Data(
            """
            {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"blitzrecorder-settings","version":"1.0"}}}
            """.utf8
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BlitzRecorderMCPConnectionTestError.unreachable
        }
        let payload = try JSONDecoder().decode(Response.self, from: data)
        guard payload.result?.serverInfo.name == "blitzrecorder" else {
            throw BlitzRecorderMCPConnectionTestError.invalidResponse
        }
    }
}

private enum BlitzRecorderMCPConnectionTestError: LocalizedError {
    case unreachable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unreachable:
            return "The local MCP server did not respond."
        case .invalidResponse:
            return "The local MCP server returned an invalid response."
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private enum MCPToolArgumentError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message):
            return message
        }
    }
}

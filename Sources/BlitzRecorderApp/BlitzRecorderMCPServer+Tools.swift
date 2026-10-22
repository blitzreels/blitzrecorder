import Foundation
import MCP

extension BlitzRecorderMCPServer {
    struct ToolCall {
        let parameters: CallTool.Parameters
        let service: MCPProjectService
    }

    nonisolated static func callTool(_ call: ToolCall) async -> CallTool.Result {
        let arguments = call.parameters.arguments
        let projectService = call.service
        do {
            switch call.parameters.name {
            case "projects_list":
                let request = try Self.projectListRequest(arguments)
                return try await Self.result(projectService.listProjects(request))
            case "project_get":
                let projectID = try Self.projectID(arguments)
                return try await Self.result(projectService.projectDetails(projectID: projectID))
            case "project_transcript":
                let projectID = try Self.projectID(arguments)
                return try await Self.result(projectService.transcript(.init(projectID: projectID)))
            case "project_frame":
                let frame = try await projectService.frame(Self.frameRequest(arguments))
                let result = try Self.result(frame.metadata)
                return .init(
                    content: result.content + [.image(
                        data: frame.jpeg.base64EncodedString(), mimeType: "image/jpeg", annotations: nil, _meta: nil
                    )],
                    structuredContent: result.structuredContent,
                    isError: false
                )
            case "projects_export_as_is":
                let request = try Self.exportStartRequest(arguments)
                return try await Self.result(projectService.startExport(request))
            case "export_status":
                let jobID = try Self.jobID(arguments)
                return try await Self.result(projectService.exportStatus(jobID: jobID))
            default:
                return Self.errorResult("Unknown BlitzRecorder tool: \(call.parameters.name).")
            }
        } catch {
            return Self.errorResult(error.localizedDescription)
        }
    }

    nonisolated private static let readOnlyAnnotations = Tool.Annotations(
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false
    )

    nonisolated private static let projectIDInputSchema: Value = .object([
        "type": "object",
        "properties": .object([
            "projectId": .object([
                "type": "string",
                "description": "Project UUID returned by projects_list.",
            ]),
        ]),
        "required": ["projectId"],
        "additionalProperties": false,
    ])

    nonisolated static let tools: [Tool] = [
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
            annotations: readOnlyAnnotations
        ),
        Tool(
            name: "project_get",
            title: "Inspect a BlitzRecorder project",
            description: "Inspect source readiness, saved export recipe, and prior exports for one project.",
            inputSchema: projectIDInputSchema,
            annotations: readOnlyAnnotations
        ),
        Tool(
            name: "project_transcript",
            title: "Inspect a project transcript",
            description: "Read the saved local transcript for one BlitzRecorder project.",
            inputSchema: projectIDInputSchema,
            annotations: readOnlyAnnotations
        ),
        Tool(
            name: "project_frame",
            title: "Inspect a recorded video frame",
            description: "Return a JPEG frame from a project's screen or camera track, without opening the app UI. "
                + "timeSeconds uses the original project timeline, matching project_transcript before saved cuts. "
                + "This is original source footage, not the edited composition. Use project_get to find available tracks.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "projectId": .object(["type": "string", "description": "Project UUID from projects_list."]),
                    "source": .object(["type": "string", "enum": ["screen", "camera"]]),
                    "timeSeconds": .object(["type": "number", "minimum": 0]),
                ]),
                "required": ["projectId", "source", "timeSeconds"],
                "additionalProperties": false,
            ]),
            annotations: readOnlyAnnotations
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
            annotations: readOnlyAnnotations
        ),
    ]

    private struct ArgumentRequest {
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

    nonisolated private static func frameRequest(_ arguments: [String: Value]?) throws -> MCPProjectFrameRequest {
        let projectID = try projectID(arguments)
        guard let rawSource = arguments?["source"]?.stringValue,
              let source = MCPProjectFrameSource(rawValue: rawSource) else {
            throw MCPToolArgumentError.invalid("source must be screen or camera.")
        }
        let time: Double
        switch arguments?["timeSeconds"] {
        case .int(let value): time = Double(value)
        case .double(let value): time = value
        default: throw MCPProjectFrameError.invalidTime
        }
        guard time.isFinite, time >= 0 else { throw MCPProjectFrameError.invalidTime }
        return .init(projectID: projectID, source: source, timeSeconds: time)
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

    nonisolated private static func uuid(_ request: ArgumentRequest) throws -> UUID {
        guard let rawValue = request.arguments?[request.key]?.stringValue,
              let id = UUID(uuidString: rawValue) else {
            throw MCPToolArgumentError.invalid("\(request.key) must be a valid UUID.")
        }
        return id
    }

    nonisolated private static func optionalString(
        _ request: ArgumentRequest
    ) throws -> String? {
        guard let value = request.arguments?[request.key] else { return nil }
        guard let string = value.stringValue else {
            throw MCPToolArgumentError.invalid("\(request.key) must be a string.")
        }
        return string
    }

    nonisolated private static func optionalBool(
        _ request: ArgumentRequest
    ) throws -> Bool? {
        guard let value = request.arguments?[request.key] else { return nil }
        guard let bool = value.boolValue else {
            throw MCPToolArgumentError.invalid("\(request.key) must be a boolean.")
        }
        return bool
    }

    nonisolated private static func optionalInt(
        _ request: ArgumentRequest
    ) throws -> Int? {
        guard let value = request.arguments?[request.key] else { return nil }
        guard let int = value.intValue else {
            throw MCPToolArgumentError.invalid("\(request.key) must be an integer.")
        }
        return int
    }

    nonisolated private static func optionalDate(
        _ request: ArgumentRequest
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

    nonisolated static func errorResult(_ message: String) -> CallTool.Result {
        .init(
            content: [.text(text: message, annotations: nil, _meta: nil)],
            isError: true
        )
    }
}

extension String {
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

import Foundation

enum MCPClientProvider: String, CaseIterable, Identifiable {
    case claudeDesktop, claudeCode, codex, cursor, vscode, windsurf, gemini, other, cloud

    var id: Self { self }

    var title: String {
        switch self {
        case .claudeDesktop: "Claude Desktop"
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .vscode: "VS Code / Copilot"
        case .windsurf: "Windsurf"
        case .gemini: "Gemini CLI"
        case .other: "Other local MCP client"
        case .cloud: "Web and mobile chats"
        }
    }

    var detail: String {
        switch self {
        case .claudeDesktop:
            "Install the local extension in Claude and approve its tools. It uses Claude's bundled Node runtime."
        case .claudeCode, .codex, .cursor, .vscode, .windsurf, .gemini:
            "Connect for your user account across projects. Keep BlitzRecorder open, then start a new agent session and approve its tools."
        case .other:
            "Add a Streamable HTTP server with the URL below. If your client only supports stdio, use the local bridge."
        case .cloud:
            "Cloud chats cannot reach this Mac's localhost. Use a local client, or copy the recording's transcript or attach an exported video."
        }
    }

    var relativeConfigurationPath: String? {
        switch self {
        case .claudeCode: ".claude.json"
        case .codex: ".codex/config.toml"
        case .cursor: ".cursor/mcp.json"
        case .vscode: "Library/Application Support/Code/User/mcp.json"
        case .windsurf: ".codeium/windsurf/mcp_config.json"
        case .gemini: ".gemini/settings.json"
        case .claudeDesktop, .other, .cloud: nil
        }
    }

    var serverKey: String { self == .vscode ? "servers" : "mcpServers" }

    var serverConfiguration: [String: String] {
        let endpoint = BlitzRecorderMCPServer.endpointURL.absoluteString
        switch self {
        case .gemini: return ["httpUrl": endpoint]
        case .windsurf: return ["serverUrl": endpoint]
        case .cursor: return ["url": endpoint]
        default: return ["type": "http", "url": endpoint]
        }
    }

    var configurationText: String {
        let value = [serverKey: ["blitzrecorder": serverConfiguration]]
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    var setupCommand: String? {
        let endpoint = BlitzRecorderMCPServer.endpointURL.absoluteString
        switch self {
        case .claudeCode: return BlitzRecorderMCPServer.claudeCodeSetupCommand
        case .codex: return BlitzRecorderMCPServer.codexSetupCommand
        case .gemini: return "gemini mcp add --scope user --transport http blitzrecorder \(endpoint)"
        case .vscode: return "code --add-mcp '{\"name\":\"blitzrecorder\",\"type\":\"http\",\"url\":\"\(endpoint)\"}'"
        default: return nil
        }
    }

    var canInstallConfiguration: Bool {
        ![.claudeDesktop, .other, .cloud].contains(self)
    }
}

enum MCPClientSetup {
    struct Request {
        let provider: MCPClientProvider
        let home: URL
    }

    enum Status: Equatable {
        case missing
        case configured
        case conflict
        case unavailable(String)

        var detail: String {
            switch self {
            case .missing: "Not configured for this user."
            case .configured: "Configuration saved. Start a new session in the client to discover the tools."
            case .conflict: "A different server already uses the name blitzrecorder. Your configuration was kept."
            case .unavailable(let message): message
            }
        }
    }

    static func status(_ request: Request) async -> Status {
        do {
            if request.provider == .codex {
                let result = try await run(.init(executable: "codex", arguments: ["mcp", "get", "blitzrecorder", "--json"], home: request.home))
                guard result.code == 0 else {
                    return result.output.localizedCaseInsensitiveContains("no mcp server") ? .missing : .unavailable("Codex could not read its MCP configuration.")
                }
                let document = try JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any]
                if document?["enabled"] as? Bool == false {
                    return .unavailable("BlitzRecorder is configured but disabled in Codex. Enable it in Codex MCP settings.")
                }
                let transport = document?["transport"] as? [String: Any]
                return transport?["url"] as? String == BlitzRecorderMCPServer.endpointURL.absoluteString ? .configured : .conflict
            }
            guard let path = request.provider.relativeConfigurationPath else { return .missing }
            let url = request.home.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
            let data = try Data(contentsOf: url)
            guard let document = try JSONSerialization.jsonObject(with: data, options: [.json5Allowed]) as? [String: Any] else {
                return .unavailable("The existing client configuration is not a JSON object. Nothing was changed.")
            }
            guard let configuredServers = document[request.provider.serverKey] else { return .missing }
            guard let servers = configuredServers as? [String: Any] else {
                return .unavailable("The client's server configuration has an unsupported format. Nothing was changed.")
            }
            guard let server = servers["blitzrecorder"] else { return .missing }
            guard let values = server as? [String: Any] else { return .conflict }
            return request.provider.serverConfiguration.allSatisfy { values[$0.key] as? String == $0.value } ? .configured : .conflict
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    static func install(_ request: Request) async throws {
        switch await status(request) {
        case .configured: return
        case .conflict: throw SetupError.message(Status.conflict.detail)
        case .unavailable(let message): throw SetupError.message(message)
        case .missing: break
        }
        if [.claudeCode, .codex, .gemini, .vscode].contains(request.provider) {
            let executable: String
            let arguments: [String]
            let endpoint = BlitzRecorderMCPServer.endpointURL.absoluteString
            switch request.provider {
            case .claudeCode, .gemini:
                executable = request.provider == .claudeCode ? "claude" : "gemini"
                arguments = ["mcp", "add", "--scope", "user", "--transport", "http", "blitzrecorder", endpoint]
            case .codex:
                executable = "codex"
                arguments = ["mcp", "add", "blitzrecorder", "--url", endpoint]
            default:
                executable = "code"
                arguments = ["--add-mcp", "{\"name\":\"blitzrecorder\",\"type\":\"http\",\"url\":\"\(endpoint)\"}"]
            }
            let result = try await run(.init(executable: executable, arguments: arguments, home: request.home))
            guard result.code == 0 else { throw SetupError.message("\(request.provider.title) could not save the connection. Use the setup command below in Terminal.") }
        } else {
            try mergeConfiguration(request)
        }
        guard await status(request) == .configured else {
            throw SetupError.message("The client did not save a matching connection. Check its MCP settings.")
        }
    }

    static func mergeConfiguration(_ request: Request) throws {
        guard let path = request.provider.relativeConfigurationPath,
              ![.codex, .vscode].contains(request.provider) else { throw SetupError.message("Use this client's setup command.") }
        let fileManager = FileManager.default
        let url = request.home.appendingPathComponent(path)
        let original = fileManager.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
        var document: [String: Any] = [:]
        if let original {
            guard let value = try JSONSerialization.jsonObject(with: original) as? [String: Any] else {
                throw SetupError.message("The existing client configuration is not a JSON object. Nothing was changed.")
            }
            document = value
        }
        if document[request.provider.serverKey] != nil, !(document[request.provider.serverKey] is [String: Any]) {
            throw SetupError.message("The client's server configuration has an unsupported format. Nothing was changed.")
        }
        var servers = document[request.provider.serverKey] as? [String: Any] ?? [:]
        if let existing = servers["blitzrecorder"] {
            guard let values = existing as? [String: Any],
                  request.provider.serverConfiguration.allSatisfy({ values[$0.key] as? String == $0.value }) else {
                throw SetupError.message(Status.conflict.detail)
            }
            return
        }
        servers["blitzrecorder"] = request.provider.serverConfiguration
        document[request.provider.serverKey] = servers
        let updated = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let current = fileManager.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
        guard current == original else { throw SetupError.message("The client changed its configuration. Try again.") }
        if let original {
            let backup = url.appendingPathExtension("blitzrecorder-\(UUID().uuidString).backup")
            try original.write(to: backup, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        }
        try updated.write(to: url, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    struct Command {
        let executable: String
        let arguments: [String]
        let home: URL
    }

    struct CommandResult {
        let code: Int32
        let output: String
    }

    static func run(_ command: Command) async throws -> CommandResult {
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let nodeRoot = command.home.appendingPathComponent(".nvm/versions/node")
            let nodeBins = ((try? fileManager.contentsOfDirectory(at: nodeRoot, includingPropertiesForKeys: nil)) ?? [])
                .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending }
                .map { $0.appendingPathComponent("bin").path }
            let paths = [command.home.appendingPathComponent(".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
                + nodeBins + (ProcessInfo.processInfo.environment["PATH"] ?? "").components(separatedBy: ":")
                + ["/Applications/Visual Studio Code.app/Contents/Resources/app/bin"]
            guard let executable = paths.map({ URL(fileURLWithPath: $0).appendingPathComponent(command.executable) })
                .first(where: { fileManager.isExecutableFile(atPath: $0.path) }) else {
                throw SetupError.message("Install \(command.executable) first, or use the setup instructions below.")
            }
            let process = Process()
            process.executableURL = executable
            process.arguments = command.arguments
            process.currentDirectoryURL = command.home
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = paths.joined(separator: ":")
            process.environment = environment
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: timeout)
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            timeout.cancel()
            return CommandResult(code: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
        }.value
    }

    enum SetupError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self { case .message(let message): message }
        }
    }
}

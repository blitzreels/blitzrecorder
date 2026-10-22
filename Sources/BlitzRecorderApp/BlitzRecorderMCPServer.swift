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
    case portInUse
    case failed(String)
}

extension BlitzRecorderMCPServerStatus {
    var servesAgents: Bool { self == .running }

    var title: String {
        switch self {
        case .disabled: "Off"
        case .stopped: "Stopped"
        case .starting: "Starting…"
        case .running: "Online"
        case .portInUse: "Port busy"
        case .failed: "Offline"
        }
    }

    var detail: String {
        switch self {
        case .disabled: "Turn on local agent access to connect."
        case .stopped: "The server is not listening."
        case .starting: "Opening the local endpoint."
        case .running: "Server available. Each AI client still needs its own connection."
        case .portInUse: "Another app is using port 18473, so agents cannot reach this copy. If it is another copy of BlitzRecorder, quit it and this one takes over."
        case .failed(let message): message
        }
    }
}

enum BlitzRecorderMCPConnectionTestStatus: Equatable {
    case notRun
    case testing
    case succeeded(MCPConnectionVerification)
    case failed(String)
}

@Observable
@MainActor
final class BlitzRecorderMCPServer {
    nonisolated static let port = 18_473
    nonisolated static let endpoint = "/mcp"
    nonisolated static let workspaceEndpoint = "/webmcp"
    nonisolated static let endpointURL = URL(string: "http://127.0.0.1:\(port)\(endpoint)")!
    nonisolated static let codexSetupCommand = "codex mcp add blitzrecorder --url \(endpointURL.absoluteString)"
    nonisolated static let claudeCodeSetupCommand = "claude mcp add --scope user --transport http blitzrecorder \(endpointURL.absoluteString)"

    nonisolated static func isEndpoint(_ value: String) -> Bool {
        guard let url = URL(string: value), url.scheme == "http", url.port == port,
              let host = url.host(percentEncoded: false),
              ["127.0.0.1", "localhost", "::1"].contains(host.lowercased()) else { return false }
        return url.path() == endpoint || url.path() == "\(endpoint)/"
    }

    nonisolated static let backgroundLaunchArgument = "--agent-background"

    private static let enabledDefaultsKey = "agents.mcpServer.enabled.v1"

    private let projectService: MCPProjectService
    private let defaults: UserDefaults
    private var httpServer: LoopbackMCPHTTPServer?
    private var portRetryTask: Task<Void, Never>?
    private(set) var isEnabled: Bool
    private(set) var status: BlitzRecorderMCPServerStatus
    private(set) var connectionTestStatus = BlitzRecorderMCPConnectionTestStatus.notRun
    private(set) var lastClientHandshake: MCPClientHandshake?

    init(coordinator: RecorderCoordinator) {
        let defaults = UserDefaults.standard
        let isEnabled = defaults.object(forKey: Self.enabledDefaultsKey) as? Bool ?? true
        self.defaults = defaults
        projectService = MCPProjectService(coordinator: coordinator)
        #if DEBUG
        MCPDebugCameraService.shared.coordinator = coordinator
        #endif
        self.isEnabled = isEnabled
        status = isEnabled ? .stopped : .disabled
    }

    func start() async {
        guard isEnabled else {
            status = .disabled
            return
        }
        guard httpServer == nil else { return }
        if status != .portInUse {
            status = .starting
        }

        let httpServer = LoopbackMCPHTTPServer(.init(
            host: "127.0.0.1",
            fallbackHosts: ["::1"],
            port: Self.port,
            endpoint: Self.endpoint,
            workspaceEndpoint: Self.workspaceEndpoint,
            workspaceData: Self.workspaceData,
            handleRequest: { [weak self] request in
                guard let self else {
                    return .error(statusCode: 503, .internalError("BlitzRecorder is unavailable."))
                }
                return await self.respond(to: request)
            }
        ))

        do {
            try await httpServer.start()
            guard isEnabled else {
                await httpServer.stop()
                status = .disabled
                return
            }
            self.httpServer = httpServer
            status = .running
            mcpLog.info("BlitzRecorder MCP listening on localhost:\(Self.port)")
        } catch {
            await httpServer.stop()
            guard LoopbackMCPHTTPServer.isAddressInUse(error) else {
                status = .failed(error.localizedDescription)
                mcpLog.error("BlitzRecorder MCP failed to start: \(error.localizedDescription, privacy: .public)")
                return
            }
            if status != .portInUse {
                mcpLog.info("BlitzRecorder MCP port \(Self.port) is in use; retrying until it is free")
            }
            status = .portInUse
            portRetryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self, self.status == .portInUse else { return }
                await self.start()
            }
        }
    }

    func respond(to request: HTTPRequest) async -> HTTPResponse {
        let transport = StatelessHTTPServerTransport(validationPipeline: StandardValidationPipeline(validators: [
            OriginValidator.localhost(port: Self.port),
            AcceptHeaderValidator(mode: .jsonOnly),
            ContentTypeValidator(),
            ProtocolVersionValidator(),
        ]))
        let server = await makeServer()
        do {
            try await server.start(transport: transport)
        } catch {
            return .error(statusCode: 500, .internalError(error.localizedDescription))
        }
        let response = await transport.handleRequest(request)
        if response.statusCode == 200, let responseData = response.bodyData,
           let reply = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
           reply["result"] is [String: Any], reply["error"] == nil,
           let body = request.body,
           let message = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           message["method"] as? String == "initialize",
           let parameters = message["params"] as? [String: Any],
           let client = parameters["clientInfo"] as? [String: Any],
           let name = client["name"] as? String, name != "blitzrecorder-settings" {
            lastClientHandshake = MCPClientHandshake(name: String(name.prefix(100)), date: Date())
        }
        await server.stop()
        return response
    }

    private func makeServer() async -> Server {
        let server = Server(
            name: "blitzrecorder",
            version: Self.serverVersion,
            capabilities: .init(tools: .init(listChanged: false))
        )
        await server.withMethodHandler(ListTools.self) { _ in
            #if DEBUG
            .init(tools: Self.tools + Self.debugTools)
            #else
            .init(tools: Self.tools)
            #endif
        }
        await server.withMethodHandler(CallTool.self) { [weak projectService] parameters in
            #if DEBUG
            if let result = await Self.callDebugTool(parameters) { return result }
            #endif
            guard let projectService else {
                return Self.errorResult("BlitzRecorder is unavailable.")
            }
            return await Self.callTool(.init(parameters: parameters, service: projectService))
        }
        return server
    }

    nonisolated private static var serverVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    func stop() async {
        portRetryTask?.cancel()
        portRetryTask = nil
        await httpServer?.stop()
        httpServer = nil
        status = isEnabled ? .stopped : .disabled
        lastClientHandshake = nil
        connectionTestStatus = .notRun
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
        guard status == .running, connectionTestStatus != .testing else { return }
        connectionTestStatus = .testing
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            let count = try await MCPConnectionProbe.test(.init(endpoint: Self.endpointURL, session: session))
            guard status == .running else { return }
            connectionTestStatus = .succeeded(.init(date: Date(), toolCount: count))
        } catch {
            guard status == .running else { return }
            connectionTestStatus = .failed(error.localizedDescription)
        }
    }

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
}

import Foundation
import MCP
@preconcurrency import NIOCore
@preconcurrency import NIOHTTP1
@preconcurrency import NIOPosix

final class LoopbackMCPHTTPServer: @unchecked Sendable {
    struct Configuration {
        let host: String
        let port: Int
        let endpoint: String
        let transport: StatelessHTTPServerTransport
    }

    private let configuration: Configuration
    private let transport: StatelessHTTPServerTransport
    private let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private var channel: Channel?

    init(_ configuration: Configuration) {
        self.configuration = configuration
        transport = configuration.transport
    }

    func start() async throws {
        let transport = self.transport
        let endpoint = configuration.endpoint
        let bootstrap = ServerBootstrap(group: eventLoopGroup)
            .serverChannelOption(ChannelOptions.backlog, value: 32)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(MCPHTTPChannelHandler(.init(
                        transport: transport,
                        endpoint: endpoint
                    )))
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

        channel = try await bootstrap.bind(
            host: configuration.host,
            port: configuration.port
        ).get()
    }

    func stop() async {
        try? await channel?.close().get()
        channel = nil
        try? await eventLoopGroup.shutdownGracefully()
    }
}

private final class MCPHTTPChannelHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    struct Configuration {
        let transport: StatelessHTTPServerTransport
        let endpoint: String
    }

    private struct RequestState {
        let head: HTTPRequestHead
        var body: ByteBuffer
    }

    private let configuration: Configuration
    private var requestState: RequestState?

    init(_ configuration: Configuration) {
        self.configuration = configuration
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            requestState = RequestState(
                head: head,
                body: context.channel.allocator.buffer(capacity: 0)
            )
        case .body(var body):
            requestState?.body.writeBuffer(&body)
        case .end:
            guard let state = requestState else { return }
            requestState = nil
            nonisolated(unsafe) let channelContext = context
            Task {
                await self.handle(.init(state: state, context: channelContext))
            }
        }
    }

    private struct HandleRequest {
        let state: RequestState
        let context: ChannelHandlerContext
    }

    private func handle(_ request: HandleRequest) async {
        let path = String(request.state.head.uri.split(separator: "?").first ?? "")
        guard path == configuration.endpoint else {
            write(.init(
                response: .error(statusCode: 404, .invalidRequest("Not Found")),
                version: request.state.head.version,
                context: request.context
            ))
            return
        }

        var headers: [String: String] = [:]
        for (name, value) in request.state.head.headers {
            if let existing = headers[name] {
                headers[name] = "\(existing), \(value)"
            } else {
                headers[name] = value
            }
        }
        let bytes = request.state.body.getBytes(
            at: 0,
            length: request.state.body.readableBytes
        ) ?? []
        let httpRequest = HTTPRequest(
            method: request.state.head.method.rawValue,
            headers: headers,
            body: bytes.isEmpty ? nil : Data(bytes),
            path: path
        )
        let response = await configuration.transport.handleRequest(httpRequest)
        write(.init(
            response: response,
            version: request.state.head.version,
            context: request.context
        ))
    }

    private struct WriteResponse: @unchecked Sendable {
        let response: HTTPResponse
        let version: HTTPVersion
        let context: ChannelHandlerContext
    }

    private func write(_ request: WriteResponse) {
        nonisolated(unsafe) let channelContext = request.context
        channelContext.eventLoop.execute {
            let body = request.response.bodyData
            var head = HTTPResponseHead(
                version: request.version,
                status: HTTPResponseStatus(statusCode: request.response.statusCode)
            )
            for (name, value) in request.response.headers {
                head.headers.add(name: name, value: value)
            }
            head.headers.replaceOrAdd(name: "Content-Length", value: String(body?.count ?? 0))
            head.headers.replaceOrAdd(name: "Connection", value: "close")
            channelContext.write(self.wrapOutboundOut(.head(head)), promise: nil)
            if let body {
                var buffer = channelContext.channel.allocator.buffer(capacity: body.count)
                buffer.writeBytes(body)
                channelContext.write(
                    self.wrapOutboundOut(.body(.byteBuffer(buffer))),
                    promise: nil
                )
            }
            channelContext.writeAndFlush(self.wrapOutboundOut(.end(nil))).whenComplete { _ in
                channelContext.close(promise: nil)
            }
        }
    }
}

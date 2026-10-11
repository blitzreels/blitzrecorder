import Foundation
import XCTest
@testable import BlitzRecorderApp

final class MCPConnectionProbeTests: XCTestCase {
    func testSuccessfulCheckIncludesDiscoveryAndAReadOnlyCall() async throws {
        let fixture = Fixture()
        defer { fixture.session.invalidateAndCancel() }
        let count = try await MCPConnectionProbe.test(fixture.configuration)
        XCTAssertEqual(count, 6)
        XCTAssertEqual(ProbeProtocol.methods, ["initialize", "notifications/initialized", "tools/list", "tools/call"])
        XCTAssertEqual(ProbeProtocol.calledTool, "projects_list")
    }

    func testSuccessfulHandshakeDoesNotHideMissingToolsOrFailedLibraryAccess() async throws {
        for failure in ["tools/list", "tools/call"] {
            let fixture = Fixture()
            defer { fixture.session.invalidateAndCancel() }
            ProbeProtocol.failingMethod = failure
            do {
                _ = try await MCPConnectionProbe.test(fixture.configuration)
                XCTFail("Expected the server check to report the failure in \(failure)")
            } catch {
                XCTAssertFalse(error.localizedDescription.isEmpty)
            }
        }
    }

    private struct Fixture {
        let session: URLSession
        var configuration: MCPConnectionProbe.Configuration {
            .init(endpoint: URL(string: "http://probe.test/mcp")!, session: session)
        }

        init() {
            ProbeProtocol.methods = []
            ProbeProtocol.calledTool = nil
            ProbeProtocol.failingMethod = nil
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [ProbeProtocol.self]
            session = URLSession(configuration: config)
        }
    }
}

private final class ProbeProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var methods: [String] = []
    nonisolated(unsafe) static var calledTool: String?
    nonisolated(unsafe) static var failingMethod: String?

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "probe.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        do {
            var data = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    guard count > 0 else { break }
                    data.append(buffer, count: count)
                }
            }
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let method = try XCTUnwrap(body["method"] as? String)
            Self.methods.append(method)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json, text/event-stream")
            var result: [String: Any] = [:]
            switch method {
            case "initialize": result = ["serverInfo": ["name": "blitzrecorder"], "protocolVersion": "2025-11-25"]
            case "tools/list":
                let names = Self.failingMethod == method ? [] : ["projects_list", "project_get", "project_transcript", "project_frame", "projects_export_as_is", "export_status"]
                result = ["tools": names.map { ["name": $0] }]
            case "tools/call":
                Self.calledTool = (body["params"] as? [String: Any])?["name"] as? String
                result = ["content": [["type": "text", "text": "{}"]], "isError": Self.failingMethod == method]
            default: break
            }
            let notification = method == "notifications/initialized"
            let response = try XCTUnwrap(HTTPURLResponse(url: request.url!, statusCode: notification ? 202 : 200, httpVersion: nil, headerFields: nil))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !notification {
                client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": body["id"] ?? 0, "result": result]))
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}

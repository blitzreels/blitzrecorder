import AppKit
import SwiftUI
import XCTest
@testable import BlitzRecorderApp

final class HostedVideoAccountTests: XCTestCase {
    @MainActor
    func testEmailSignInAndSubscriptionRefreshUseOnlyBlitzRecorder() async throws {
        let fixture = AccountFixture()
        defer { fixture.cleanup() }
        let controller = fixture.controller
        await controller.refresh()
        XCTAssertTrue(controller.hasCheckedAccount)
        XCTAssertFalse(controller.isConnected)
        await controller.requestCode(email: "owner@example.test")
        XCTAssertEqual(controller.challenge?.email, "owner@example.test")
        await controller.verifyCode("123456")
        XCTAssertTrue(controller.isConnected)
        XCTAssertFalse(controller.isSubscribed)
        XCTAssertNil(controller.challenge)
        fixture.server.active = true
        await controller.refresh()
        XCTAssertTrue(controller.isSubscribed)
        XCTAssertEqual(controller.account?.email, "owner@example.test")
        XCTAssertTrue(fixture.server.requests.allSatisfy { $0.url?.host == "account.hosting.test" })
        XCTAssertFalse(fixture.server.requests.contains { $0.url?.path.hasSuffix("/connect") == true })
        await controller.disconnect()
        XCTAssertFalse(controller.isConnected)
        XCTAssertNil(fixture.credentials.load())
    }

    @MainActor
    func testAccountChecksDoNotBecomeUploadProgressAndDuplicateActionsAreCoalesced() async throws {
        let fixture = AccountFixture()
        defer { fixture.cleanup() }
        let controller = fixture.controller
        let check = Task { await controller.refresh() }
        await Task.yield()
        XCTAssertEqual(controller.accountOperation, .checking)
        XCTAssertFalse(controller.isRunning)
        XCTAssertNil(controller.transferProgress)
        await controller.refresh()
        await check.value
        XCTAssertEqual(fixture.server.requests.filter { $0.url?.path.hasSuffix("/plan") == true }.count, 1)
        let send = Task { await controller.requestCode(email: "owner@example.test") }
        await Task.yield()
        XCTAssertEqual(controller.accountOperation, .sendingCode)
        await controller.requestCode(email: "owner@example.test")
        await send.value
        XCTAssertEqual(fixture.server.requests.filter { $0.url?.path.hasSuffix("/request") == true }.count, 1)
    }

    @MainActor
    func testExpiredConnectionShowsSignInAndKeepsSelectedFile() async throws {
        let fixture = AccountFixture()
        defer { fixture.cleanup() }
        try fixture.credentials.save(fixture.server.token)
        let controller = fixture.controller
        let file = URL(fileURLWithPath: "/tmp/retained-export.mp4")
        controller.select(.init(fileURL: file, projectPath: nil))
        await controller.refresh()
        XCTAssertTrue(controller.isConnected)
        fixture.server.rejectAccount = true
        await controller.refresh()
        XCTAssertFalse(controller.isConnected)
        XCTAssertNil(fixture.credentials.load())
        XCTAssertEqual(controller.fileURL, file)
        XCTAssertNotNil(controller.accountMessage)
    }

    @MainActor
    func testSelectedExportBelongsOnlyToItsProjectAndSurvivesReopening() throws {
        let fixture = AccountFixture()
        defer { fixture.cleanup() }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        try Data(repeating: 1, count: 128).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        fixture.controller.select(.init(fileURL: file, projectPath: "/recordings/first"))
        XCTAssertTrue(fixture.controller.belongsToProject("/recordings/first"))
        XCTAssertFalse(fixture.controller.belongsToProject("/recordings/second"))
        XCTAssertFalse(fixture.controller.belongsToProject(nil))
        let reopened = HostedVideoShareController(client: .init(origin: fixture.credentials.origin, session: fixture.session))
        XCTAssertTrue(reopened.belongsToProject("/recordings/first"))
        fixture.controller.select(.init(fileURL: file, projectPath: "/recordings/second"))
        XCTAssertFalse(fixture.controller.belongsToProject("/recordings/first"))
        XCTAssertTrue(fixture.controller.belongsToProject("/recordings/second"))
    }

    @MainActor
    func testShareInspectorFitsNarrowWidthsAcrossAccountStates() async throws {
        let fixture = AccountFixture()
        defer { fixture.cleanup() }
        let controller = fixture.controller
        await controller.refresh()
        try snapshot(.init(controller: controller, name: "email", preparation: nil))
        await controller.requestCode(email: "owner@example.test")
        try snapshot(.init(controller: controller, name: "code", preparation: nil))
        await controller.verifyCode("123456")
        try snapshot(.init(controller: controller, name: "plan", preparation: nil))
        fixture.server.active = true
        await controller.refresh()
        let ready = HostedVideoSharePanel.ExportPreparation(title: "How to record a useful walkthrough",
            summary: "2560 × 1440 · 30 fps", status: nil, export: {})
        try snapshot(.init(controller: controller, name: "ready", preparation: ready))
        let saving = HostedVideoSharePanel.ExportPreparation(title: ready.title, summary: ready.summary,
            status: .exporting(.init(title: "Exporting", percentage: "42%", detail: nil, value: 0.42)), export: {})
        try snapshot(.init(controller: controller, name: "saving", preparation: saving))
    }

    private struct Snapshot {
        let controller: HostedVideoShareController
        let name: String
        let preparation: HostedVideoSharePanel.ExportPreparation?
    }

    @MainActor private func snapshot(_ request: Snapshot) throws {
        for width in [312.0, 400.0] {
            let host = NSHostingView(rootView: HostedVideoSharePanel(controller: request.controller,
                preparation: request.preparation, newExport: {}, close: {}).frame(width: width, height: 660).preferredColorScheme(.dark))
            host.setFrameSize(host.fittingSize)
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(host.fittingSize.width, width, accuracy: 1)
            if let directory = ProcessInfo.processInfo.environment["BLITZRECORDER_EXPORT_UI_PROOF"] {
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let file = URL(fileURLWithPath: directory).appendingPathComponent("sharing-\(request.name)-\(Int(width)).png")
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: file)
            }
        }
    }
}

@MainActor private final class AccountFixture {
    let server = AccountServer()
    let credentials = HostingCredentialStore(origin: URL(string: "https://account.hosting.test")!)
    let session: URLSession
    let controller: HostedVideoShareController

    init() {
        credentials.clear()
        AccountProtocol.server = server
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AccountProtocol.self]
        session = URLSession(configuration: configuration)
        controller = HostedVideoShareController(client: .init(origin: credentials.origin, session: session))
    }

    func cleanup() {
        session.invalidateAndCancel()
        credentials.clear()
        UserDefaults.standard.removeObject(forKey: "HostingExport:https://account.hosting.test")
        UserDefaults.standard.removeObject(forKey: "HostingProject:https://account.hosting.test")
        AccountProtocol.server = nil
    }
}

private final class AccountServer: @unchecked Sendable {
    let token = "brh_" + String(repeating: "a", count: 43)
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private var isActive = false
    private var rejectsAccount = false
    var requests: [URLRequest] { lock.withLock { recorded } }
    var active: Bool {
        get { lock.withLock { isActive } }
        set { lock.withLock { isActive = newValue } }
    }
    var rejectAccount: Bool {
        get { lock.withLock { rejectsAccount } }
        set { lock.withLock { rejectsAccount = newValue } }
    }

    func response(_ request: URLRequest) throws -> (Int, Data) {
        try lock.withLock {
            recorded.append(request)
            let path = request.url!.path
            let body: [String: Any]
            if path.hasSuffix("/plan") {
                body = ["name": "BlitzRecorder Hosting", "amount": 900, "currency": "eur", "storageBytes": 50_000_000_000,
                    "uploadSeconds": 18000, "uploadWindowDays": 30, "maximumResolution": 1080, "retentionDaysAfterExpiry": 30, "available": true]
            } else if path.hasSuffix("/request") {
                body = ["challenge": String(repeating: "b", count: 43), "email": "owner@example.test", "expiresIn": 600, "retryAfter": 60]
            } else if path.hasSuffix("/disconnect") {
                body = ["disconnected": true]
            } else if path.hasSuffix("/account"), rejectsAccount {
                return (401, Data("{\"error\":\"Your connection expired.\"}".utf8))
            } else {
                body = ["token": token, "active": isActive, "email": "owner@example.test"]
            }
            return (200, try JSONSerialization.data(withJSONObject: body))
        }
    }
}

private final class AccountProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var storedServer: AccountServer?
    static var server: AccountServer? {
        get { lock.withLock { storedServer } }
        set { lock.withLock { storedServer = newValue } }
    }
    private var work: DispatchWorkItem?
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "account.hosting.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let work = DispatchWorkItem { [self] in
            do {
                let result = try Self.server!.response(request)
                let response = HTTPURLResponse(url: request.url!, statusCode: result.0, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: result.1)
                client?.urlProtocolDidFinishLoading(self)
            } catch { client?.urlProtocol(self, didFailWithError: error) }
        }
        self.work = work
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.04, execute: work)
    }
    override func stopLoading() { work?.cancel() }
}

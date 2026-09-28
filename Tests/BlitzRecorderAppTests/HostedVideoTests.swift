import AVFoundation
import XCTest
@testable import BlitzRecorderApp

final class HostedVideoTests: XCTestCase {
    @MainActor
    func testUnavailableHostingDoesNotStartAccountConnection() async throws {
        let server = HostingTestServer(bytes: 10)
        HostingTestProtocol.server = server
        defer { HostingTestProtocol.server = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HostingTestProtocol.self]
        let network = URLSession(configuration: configuration)
        defer { network.invalidateAndCancel() }
        let controller = HostedVideoShareController(client: .init(origin: URL(string: "https://hosting.test")!, session: network))
        await controller.refresh()
        XCTAssertNil(controller.plan)
        XCTAssertFalse(controller.isRunning)
        XCTAssertEqual(controller.message, "Video hosting is not available on this server yet. You can save your video to this Mac.")
        XCTAssertEqual(server.requests.map { $0.url?.path }, ["/api/hosting/plan"])
    }

    @MainActor
    func testSourceQualityCloudExportKeeps1440pAndFrameRateWithEdits() async throws {
        let fixture = try SyntheticRecording()
        try await fixture.writeVideo(.init(url: fixture.take.screenURL, frames: 30))
        let recipe = EditorExportRecipe.make(.init(
            preset: .fast, sourceResolution: .p1440, sourceFramesPerSecond: 30,
            customResolution: .p720, customFramesPerSecond: 24, customVideoQuality: .compact,
            layout: .horizontal, layoutCount: 1, audioBitrate: 192_000, duration: 1,
            playbackRate: 1.3, destination: .link))
        var settings = recipe.profile.applying(to: fixture.settings)
        settings.outputVideoFormat = .mp4
        let output = fixture.root.appendingPathComponent("cloud-master.mp4")
        var edits = TimelineEdits.empty
        edits.cuts = [.init(start: 0.2, end: 0.4, kind: .manual, source: .user)]
        let url = try await Merger.exportFinalVideo(.init(
            take: fixture.take, settings: settings, sceneEvents: [], backgroundMusic: nil,
            destinationURL: output, progressHandler: nil, timelineEdits: edits, playbackRate: 1.3))
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let video = try XCTUnwrap(tracks.first)
        let size = try await video.load(.naturalSize)
        let fps = try await video.load(.nominalFrameRate)
        let duration = try await asset.load(.duration)
        let formats = try await video.load(.formatDescriptions)
        XCTAssertEqual(size, CGSize(width: 2560, height: 1440))
        XCTAssertEqual(fps, 30, accuracy: 0.1)
        XCTAssertEqual(duration.seconds, 0.8 / 1.3, accuracy: 0.1)
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(try XCTUnwrap(formats.first)), kCMVideoCodecType_HEVC)
        let decoded = try await SyntheticRecording.inspectVideo(url)
        XCTAssertGreaterThan(decoded.frames, 15)
        if let directory = ProcessInfo.processInfo.environment["BLITZRECORDER_EXPORT_UI_PROOF"] {
            try FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: directory).appendingPathComponent("cloud-master.mp4"))
        }
    }

    func testUploadDelegateReportsBytesBeforePartCompletionAndRejectsRedirects() async throws {
        let updates = AsyncStream<Int64>.makeStream()
        let delegate = HostingUploadDelegate(continuation: updates.continuation)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.uploadTask(with: URLRequest(url: URL(string: "https://upload.test/part")!), from: Data())
        try await Task.sleep(for: .milliseconds(110))
        delegate.urlSession(session, task: task, didSendBodyData: 100, totalBytesSent: 100, totalBytesExpectedToSend: 1000)
        delegate.urlSession(session, task: task, didSendBodyData: 900, totalBytesSent: 1000, totalBytesExpectedToSend: 1000)
        updates.continuation.finish()
        var values: [Int64] = []
        for await value in updates.stream { values.append(value) }
        XCTAssertEqual(values, [100, 1000])
        let response = HTTPURLResponse(url: task.originalRequest!.url!, statusCode: 307, httpVersion: nil, headerFields: nil)!
        delegate.urlSession(session, task: task, willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: URL(string: "https://foreign.test")!)) { request in
                XCTAssertNil(request)
            }
    }

    func testR2StreamingRoundTripWhenRequested() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let origin = env["HOSTING_SMOKE_ORIGIN"], let token = env["HOSTING_SMOKE_TOKEN"],
              let file = env["HOSTING_SMOKE_FILE"], let receipt = env["HOSTING_SMOKE_RECEIPT"] else {
            throw XCTSkip("Requires an isolated hosting validation service.")
        }
        let client = HostingClient(origin: try XCTUnwrap(URL(string: origin)), session: .shared)
        let duration = try await AVURLAsset(url: URL(fileURLWithPath: file)).load(.duration).seconds
        let details = HostedVideoDetails(version: 1, summary: "Streaming integration check", language: "en", recordedAt: nil,
            transcript: [.init(start: 0, end: min(2, duration), text: "A generated test video.", speaker: nil)],
            chapters: [.init(start: 0, title: "Test chapter", summary: nil)])
        let url = try await client.upload(.init(fileURL: URL(fileURLWithPath: file), token: token,
            metadata: .init(title: "Hosting integration check", details: details), progress: { _ in }))
        XCTAssertEqual(url.host, URL(string: origin)?.host)
        try Data(url.absoluteString.utf8).write(to: URL(fileURLWithPath: receipt))
    }

    func testMetadataNeverIncludesRemovedWordsAndMapsChaptersAtFractionalSpeed() throws {
        let transcript = RecordingTranscriptAssembler.assemble(.init(mediaPath: "/private/local/path", generatedAt: Date(),
            duration: 10, confidence: 1, text: "hello secret world", suggestedTitle: nil,
            words: [.init(text: "hello", startTime: 0, endTime: 1, confidence: 1),
                    .init(text: "secret", startTime: 2, endTime: 3, confidence: 1),
                    .init(text: "world", startTime: 5, endTime: 6, confidence: 1)], diarizedIntervals: []))
        let cuts = [TimelineCut(start: 2, end: 4, kind: .manual, source: .user)]
        let details = try XCTUnwrap(HostedVideoDetails.project(.init(transcript: transcript,
            chapters: [.init(time: 0, title: "Start"), .init(time: 2, endTime: 3, title: "Secret"), .init(time: 4, title: "Next")],
            cuts: cuts, playbackRate: 1.3, outputDuration: 8 / 1.3, recordedAt: Date(timeIntervalSince1970: 0))))
        XCTAssertEqual(details.transcript.map(\.text), ["hello", "world"])
        XCTAssertEqual(details.transcript[1].start, 3 / 1.3, accuracy: 0.001)
        XCTAssertEqual(details.chapters.map(\.title), ["Start", "Next"])
        XCTAssertEqual(details.chapters[1].start, 2 / 1.3, accuracy: 0.001)
        let json = String(decoding: try JSONEncoder().encode(details), as: UTF8.self)
        XCTAssertFalse(json.contains("secret"))
        XCTAssertFalse(json.contains("private/local"))
        XCTAssertNil(HostedVideoDetails.project(.init(transcript: transcript, chapters: [], cuts: cuts,
            playbackRate: 1, outputDuration: 10, recordedAt: Date())))
    }

    func testSharingURLRejectsRedirectsAndForeignPaths() throws {
        let client = HostingClient(origin: URL(string: "https://example.com")!, session: .shared)
        XCTAssertThrowsError(try client.shareURL("https://other.example/s/video"))
        XCTAssertThrowsError(try client.shareURL("//other.example/s/video"))
        XCTAssertThrowsError(try client.shareURL("/s/../../admin"))
        XCTAssertEqual(try client.shareURL("/s/abcdefghijklmnopqrstuvwx").absoluteString,
                       "https://example.com/s/abcdefghijklmnopqrstuvwx")
    }

    func testResumingUploadSkipsSavedPartsRetriesAndReturnsSameLink() async throws {
        let fixture = try SyntheticRecording()
        try await fixture.writeVideo(.init(url: fixture.take.screenURL, frames: 60))
        let bytes = try XCTUnwrap(fixture.take.screenURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        let server = HostingTestServer(bytes: bytes)
        HostingTestProtocol.server = server
        defer { HostingTestProtocol.server = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HostingTestProtocol.self]
        let network = URLSession(configuration: configuration)
        defer { network.invalidateAndCancel() }
        let client = HostingClient(origin: URL(string: "https://hosting.test")!, session: network)
        let progress = HostingTestProgress()
        let request = HostingClient.Upload(fileURL: fixture.take.screenURL, token: "test-token",
            metadata: .init(title: "Test video", details: .empty), progress: { await progress.append($0) })
        let first = try await client.upload(request)
        let updates = await progress.values
        XCTAssertEqual(updates.first, .preparing)
        XCTAssertEqual(updates.last, .processing)
        let uploaded = updates.compactMap { update -> HostingUploadBytes? in
            guard case .uploading(let bytes) = update else { return nil }
            return bytes
        }
        XCTAssertEqual(uploaded.first?.sent, Int64(bytes / 2))
        XCTAssertEqual(uploaded.last?.sent, Int64(bytes))
        XCTAssertTrue(uploaded.allSatisfy { (0...1).contains($0.fraction) })
        let second = try await client.upload(request)
        XCTAssertEqual(first, second)
        let requests = server.requests
        XCTAssertFalse(requests.contains { $0.url?.path == "/part/1" })
        XCTAssertEqual(requests.filter { $0.url?.path == "/part/2" }.count, 2)
        XCTAssertEqual(requests.filter { $0.url?.path.hasSuffix("/complete") == true }.count, 1)
        XCTAssertTrue(requests.filter { $0.url?.host == "upload.test" }.allSatisfy {
            $0.value(forHTTPHeaderField: "Authorization") == nil
        })
    }
}

private final class HostingTestServer: @unchecked Sendable {
    private let lock = NSLock()
    private let bytes: Int
    private var completed = false
    private var failedOnce = false
    private var captured: [URLRequest] = []
    private let id = UUID().uuidString.lowercased()
    init(bytes: Int) { self.bytes = bytes }
    var requests: [URLRequest] { lock.withLock { captured } }

    func respond(_ request: URLRequest) throws -> (Int, Data) {
        try lock.withLock {
            captured.append(request)
            let partBytes = max(1, bytes / 2)
            let url = try XCTUnwrap(request.url)
            if url.path.hasSuffix("/plan") { return (404, Data()) }
            if url.host == "upload.test" {
                if url.path == "/part/2", !failedOnce { failedOnce = true; return (503, Data()) }
                return (200, Data())
            }
            if url.path.hasSuffix("/parts") {
                let number = captured.filter { $0.url?.path.hasSuffix("/parts") == true }.count == 1 ? 2 : failedOnce && captured.filter({ $0.url?.path == "/part/2" }).count < 2 ? 2 : 3
                return (200, try JSONSerialization.data(withJSONObject: ["url": "https://upload.test/part/\(number)"]))
            }
            if url.path.hasSuffix("/details") { return (200, Data("{\"saved\":true}".utf8)) }
            if url.path.hasSuffix("/complete") { completed = true }
            let asset: [String: Any] = ["id": id, "status": completed ? "ready" : "uploading",
                "sharePath": completed ? "/s/abcdefghijklmnopqrstuvwx" : NSNull(), "error": NSNull(),
                "partBytes": partBytes, "parts": (bytes + partBytes - 1) / partBytes,
                "uploadedParts": [["number": 1, "bytes": partBytes]]]
            return (200, try JSONSerialization.data(withJSONObject: asset))
        }
    }
}

private final class HostingTestProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var storedServer: HostingTestServer?
    static var server: HostingTestServer? {
        get { lock.withLock { storedServer } }
        set { lock.withLock { storedServer = newValue } }
    }
    override class func canInit(with request: URLRequest) -> Bool { ["hosting.test", "upload.test"].contains(request.url?.host ?? "") }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let server = try XCTUnwrap(Self.server)
            let (status, data) = try server.respond(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private actor HostingTestProgress {
    private(set) var values: [HostingClient.Progress] = []
    func append(_ value: HostingClient.Progress) { values.append(value) }
}

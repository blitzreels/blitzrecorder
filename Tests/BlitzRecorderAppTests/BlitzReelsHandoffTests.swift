import XCTest
@testable import BlitzRecorderApp

final class BlitzReelsHandoffTests: XCTestCase {
    func testPKCEUsesS256AndRejectsAnUnrelatedCallback() throws {
        let proof = BlitzReelsOAuthProof(
            verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", state: "expected"
        )
        XCTAssertEqual(proof.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let redirect = URL(string: "blitzrecorder-dev://oauth/callback")!
        XCTAssertEqual(try proof.code(.init(
            url: URL(string: "blitzrecorder-dev://oauth/callback?state=expected&code=one-use-code")!, redirectURI: redirect
        )), "one-use-code")
        for invalid in [
            "blitzrecorder-dev://oauth/callback?state=wrong&code=code",
            "blitzrecorder-dev://oauth/callback?code=code",
            "blitzrecorder-dev://other/callback?state=expected&code=code",
            "blitzrecorder://oauth/callback?state=expected&code=code",
            "blitzrecorder-dev://oauth/wrong?state=expected&code=code",
            "blitzrecorder-dev://oauth/callback?state=expected&code=code&code=other",
            "blitzrecorder-dev://oauth/callback?state=expected&state=other&code=code",
            "blitzrecorder-dev://oauth/callback?state=expected&error=access_denied"
        ] {
            XCTAssertThrowsError(try proof.code(.init(url: URL(string: invalid)!, redirectURI: redirect)))
        }
    }

    func testProofIsFreshForEachConnection() throws {
        let first = try BlitzReelsOAuthProof.make()
        let second = try BlitzReelsOAuthProof.make()
        XCTAssertNotEqual(first.state, second.state)
        XCTAssertNotEqual(first.verifier, second.verifier)
        XCTAssertEqual(first.verifier.count, 43)
        XCTAssertEqual(first.state.count, 43)
    }

    func testHandoffOpensWholeVideoCreateWithoutPuttingCredentialsInURL() {
        let client = BlitzReelsHTTPClient(origin: URL(string: "https://blitzreels.com")!, session: .shared)
        let url = client.createURL(.init(assetID: "asset with spaces", organizationID: "workspace"))
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let query = Dictionary(uniqueKeysWithValues: parts.queryItems!.map { ($0.name, $0.value!) })
        XCTAssertEqual(parts.path, "/dashboard/create")
        XCTAssertEqual(query, [
            "mode": "video", "source": "blitzrecorder", "asset": "asset with spaces", "org": "workspace"
        ])
    }

    func testExpiredRefreshAndQuotaErrorsRemainActionable() throws {
        let url = URL(string: "https://blitzreels.com/api/oauth/token")!
        let expired = HTTPURLResponse(url: url, statusCode: 400, httpVersion: nil, headerFields: nil)!
        XCTAssertThrowsError(try BlitzReelsHTTPClient.validate(.init(
            data: Data(#"{"error":"invalid_grant"}"#.utf8), response: expired
        ))) { error in
            guard case BlitzReelsHandoffError.signInAgain = error else {
                return XCTFail("An expired refresh token must offer reconnection.")
            }
        }
        let quota = HTTPURLResponse(url: url, statusCode: 402, httpVersion: nil, headerFields: nil)!
        XCTAssertThrowsError(try BlitzReelsHTTPClient.validate(.init(
            data: Data(#"{"error":{"message":"Workspace storage is full."}}"#.utf8), response: quota
        ))) { error in
            XCTAssertEqual(error.localizedDescription, "Workspace storage is full.")
            guard case BlitzReelsHandoffError.planAccess = error else {
                return XCTFail("Quota errors must expose the billing action.")
            }
        }
    }

    func testNewAccountsOfferSetupInsteadOfAnEndlessReconnect() throws {
        let response = HTTPURLResponse(
            url: URL(string: "https://blitzreels.com/api/blitzrecorder/connection")!,
            statusCode: 403, httpVersion: nil, headerFields: nil
        )!
        XCTAssertThrowsError(try BlitzReelsHTTPClient.validate(.init(
            data: Data(#"{"error":{"message":"Finish account setup.","onboarding_url":"https://blitzreels.com/dashboard/onboarding"}}"#.utf8),
            response: response
        ))) { error in
            guard case BlitzReelsHandoffError.accountSetup = error else {
                return XCTFail("A new account needs a setup action.")
            }
            XCTAssertEqual(error.localizedDescription, "Finish account setup.")
        }
    }

    func testExportPickerExcludesSourcesMissingFilesAndMOVAndKeepsAllMP4Variants() throws {
        var settings = RecordingSettings()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        settings.outputDirectory = directory
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        var document = try JSONSerialization.jsonObject(with: Data(contentsOf: take.projectURL)) as! [String: Any]
        let paths = ["first.mp4", "second.mp4", "source.mp4", "movie.mov"].map { directory.appendingPathComponent($0).path }
        for path in paths { try Data([1]).write(to: URL(fileURLWithPath: path)) }
        document["sources"] = [["role": "screen", "path": paths[2], "exists": true]]
        document["finalVideoPath"] = paths[0]
        document["exports"] = (paths + [directory.appendingPathComponent("missing.mp4").path]).enumerated().map { index, path in
            [
                "id": UUID().uuidString,
                "createdAt": ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: Double(index))),
                "path": path, "format": "mp4",
                "resolution": "1080p", "framesPerSecond": 30, "quality": "high"
            ] as [String: Any]
        }
        try JSONSerialization.data(withJSONObject: document).write(to: take.projectURL)
        let project = try store.loadRecordingProject(at: take.projectURL)
        XCTAssertEqual(BlitzReelsExportFiles.files(project).map(\.path), [paths[1], paths[0]])
    }

    func testReceiptIdentityChangesWhenExportBytesChange() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("original export".utf8).write(to: url)
        let first = try BlitzReelsExportFiles.fingerprint(url)
        XCTAssertEqual(first, try BlitzReelsExportFiles.fingerprint(url))
        try Data("different bytes".utf8).write(to: url)
        XCTAssertNotEqual(first, try BlitzReelsExportFiles.fingerprint(url))
    }
}

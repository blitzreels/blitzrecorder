import XCTest
@testable import BlitzRecorderTransport

final class JSONMessageCodecTests: XCTestCase {
    func testManifestRoundTrip() throws {
        let manifest = FixtureManifest(fileName: "camera.mov", byteCount: 1024)

        let data = try JSONMessageCodec.encode(manifest)
        let decoded = try JSONMessageCodec.decode(FixtureManifest.self, from: data)

        XCTAssertEqual(decoded, manifest)
    }
}

private struct FixtureManifest: Codable, Equatable {
    var fileName: String
    var byteCount: Int64
}

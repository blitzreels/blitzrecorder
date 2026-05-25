import Foundation
import Network
import XCTest
@testable import BlitzRecorderTransport

final class JSONLineFramerTests: XCTestCase {
    func testSplitsCompleteFramesAcrossChunks() throws {
        var framer = JSONLineFramer()

        XCTAssertEqual(try framer.append(Data(#"{"a":1}"#.utf8)), [])
        let frames = try framer.append(Data("\n{\"b\":2}\n".utf8))

        XCTAssertEqual(frames.map { String(decoding: $0, as: UTF8.self) }, [
            #"{"a":1}"#,
            #"{"b":2}"#
        ])
    }

    func testThrowsWhenBufferedFrameIsTooLarge() {
        var framer = JSONLineFramer(maximumFrameLength: 4)

        XCTAssertThrowsError(try framer.append(Data("12345".utf8))) { error in
            XCTAssertEqual(error as? JSONFrameConnectionError, .frameTooLarge(5))
        }
    }

    func testDirectTCPServiceBuildsHostPortEndpoint() {
        let service = DiscoveredBonjourService.directTCP(host: "192.168.1.10", port: 49152)

        XCTAssertEqual(service.id, "direct:192.168.1.10:49152")
        XCTAssertEqual(service.endpointDescription, "192.168.1.10:49152")
        guard case .hostPort(let host, let port) = service.endpoint else {
            return XCTFail("Expected hostPort endpoint")
        }
        XCTAssertEqual("\(host)", "192.168.1.10")
        XCTAssertEqual(port.rawValue, 49152)
    }
}

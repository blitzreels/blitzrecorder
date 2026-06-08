import BlitzRecorderTransport
import Network
@testable import BlitzRecorderApp
import XCTest

@MainActor
final class RemoteCameraControlClientTests: XCTestCase {
    func testConnectReusesExistingConnectionForSameServiceByDefault() {
        let client = RemoteCameraControlClient()
        let service = makeService()

        client.connect(to: service)
        client.connect(to: service)

        XCTAssertEqual(client.connectionAttemptCount, 1)
        client.cancel()
    }

    func testForcedReconnectStartsFreshConnectionForSameService() {
        let client = RemoteCameraControlClient()
        let service = makeService()

        client.connect(to: service)
        client.connect(to: service, forceReconnect: true)

        XCTAssertEqual(client.connectionAttemptCount, 2)
        client.cancel()
    }

    private func makeService() -> DiscoveredBonjourService {
        DiscoveredBonjourService(
            id: "Alice-iPhone._blitzrecorder-camera._tcp.local.",
            name: "Alice iPhone",
            endpointDescription: "_blitzrecorder-camera._tcp.local.",
            endpoint: .hostPort(host: "127.0.0.1", port: 9)
        )
    }
}

import XCTest
@testable import BlitzRecorderCore

final class RemoteCameraTransferProtocolTests: XCTestCase {
    func testRemoteCameraTransferProtocolNormalizesTransferState() {
        let takeID = UUID()

        XCTAssertEqual(RemoteCameraTransferProtocol.clampedResumeOffset(-10, fileSize: 100), 0)
        XCTAssertEqual(RemoteCameraTransferProtocol.clampedResumeOffset(150, fileSize: 100), 100)
        XCTAssertEqual(
            RemoteCameraTransferProtocol.chunkDisposition(offset: 5, receivedByteCount: 5),
            .append
        )
        XCTAssertEqual(
            RemoteCameraTransferProtocol.chunkDisposition(offset: 2, receivedByteCount: 5),
            .alreadyReceived(acknowledgedByteCount: 5)
        )
        XCTAssertEqual(
            RemoteCameraTransferProtocol.chunkDisposition(offset: 8, receivedByteCount: 5),
            .gap(expectedOffset: 5, receivedOffset: 8)
        )
        XCTAssertFalse(RemoteCameraTransferProtocol.isAcknowledgementValid(
            receivedByteCount: 4,
            expectedMinimumByteCount: 5
        ))
        XCTAssertTrue(RemoteCameraTransferProtocol.shouldCompleteImport(
            receivedByteCount: 100,
            expectedByteCount: 100
        ))
        XCTAssertEqual(
            RemoteCameraTransferProtocol.progress(
                takeID: takeID,
                transferredByteCount: 120,
                expectedByteCount: 100
            ),
            RemoteCameraTransferProgress(
                takeID: takeID,
                transferredByteCount: 100,
                expectedByteCount: 100
            )
        )
    }
}

import Foundation
@testable import BlitzRecorderApp
import XCTest

final class RemoteCameraTakeIDResolverTests: XCTestCase {
    func testUsesActiveTakeIDFirst() {
        let activeTakeID = UUID()
        let pendingTakeID = UUID()
        let take = makeTake()

        let resolved = RemoteCameraTakeIDResolver.takeID(
            activeTakeID: activeTakeID,
            pendingTransferDestinationURLs: [pendingTakeID: take.cameraURL],
            pendingImports: [makePendingImport(takeID: pendingTakeID, take: take)],
            take: take
        )

        XCTAssertEqual(resolved, activeTakeID)
    }

    func testRecoversTakeIDFromPendingTransferDestination() {
        let takeID = UUID()
        let take = makeTake()

        let resolved = RemoteCameraTakeIDResolver.takeID(
            activeTakeID: nil,
            pendingTransferDestinationURLs: [takeID: take.cameraURL],
            pendingImports: [],
            take: take
        )

        XCTAssertEqual(resolved, takeID)
    }

    func testRecoversTakeIDFromPendingImportScratchDirectory() {
        let takeID = UUID()
        let take = makeTake()

        let resolved = RemoteCameraTakeIDResolver.takeID(
            activeTakeID: nil,
            pendingTransferDestinationURLs: [:],
            pendingImports: [makePendingImport(takeID: takeID, take: take)],
            take: take
        )

        XCTAssertEqual(resolved, takeID)
    }

    private func makeTake() -> RecordingTake {
        let scratchDirectory = URL(fileURLWithPath: "/tmp/blitzrecorder-test-take", isDirectory: true)
        return RecordingTake(
            scratchDirectory: scratchDirectory,
            screenURL: scratchDirectory.appendingPathComponent("screen.mov"),
            cameraURL: scratchDirectory.appendingPathComponent("camera.mov"),
            audioURL: scratchDirectory.appendingPathComponent("audio.m4a"),
            systemAudioURL: scratchDirectory.appendingPathComponent("system-audio.m4a"),
            transcriptURL: scratchDirectory.appendingPathComponent("transcript.txt"),
            finalVideoURL: URL(fileURLWithPath: "/tmp/blitzrecorder-test-final.mov"),
            outputVideoFormat: .mov,
            titleSlug: nil
        )
    }

    private func makePendingImport(takeID: UUID, take: RecordingTake) -> RemoteCameraPendingImport {
        RemoteCameraPendingImport(
            takeID: takeID,
            serviceID: "iphone",
            scratchDirectory: take.scratchDirectory,
            destinationURL: take.cameraURL,
            createdAt: Date(),
            expectedByteCount: nil
        )
    }
}

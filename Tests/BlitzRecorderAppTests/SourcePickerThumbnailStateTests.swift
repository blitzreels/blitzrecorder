import AppKit
import XCTest
@testable import BlitzRecorderApp

@MainActor
final class SourcePickerThumbnailStateTests: XCTestCase {
    func testLateThumbnailCannotReplaceNewSourcePreview() async throws {
        let state = SourcePickerThumbnailState()
        let started = expectation(description: "First source starts loading")
        var continuation: CheckedContinuation<NSImage?, Never>?
        let oldImage = NSImage(size: CGSize(width: 20, height: 20))
        let newImage = NSImage(size: CGSize(width: 40, height: 20))
        let first = Task {
            await state.load(.init(id: .init(sourceID: "old", revision: 0), load: {
                await withCheckedContinuation {
                    continuation = $0
                    started.fulfill()
                }
            }))
        }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(state.isLoading)
        await state.load(.init(id: .init(sourceID: "new", revision: 0), load: { newImage }))
        try XCTUnwrap(continuation).resume(returning: oldImage)
        await first.value
        XCTAssertEqual(state.id?.sourceID, "new")
        XCTAssertTrue(state.image === newImage)
        XCTAssertFalse(state.isLoading)
    }

    func testCancelledThumbnailIsDiscarded() async throws {
        let state = SourcePickerThumbnailState()
        let started = expectation(description: "Capture starts")
        var continuation: CheckedContinuation<NSImage?, Never>?
        let task = Task {
            await state.load(.init(id: .init(sourceID: "window", revision: 0), load: {
                await withCheckedContinuation {
                    continuation = $0
                    started.fulfill()
                }
            }))
        }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        try XCTUnwrap(continuation).resume(returning: NSImage(size: CGSize(width: 20, height: 20)))
        await task.value
        XCTAssertNil(state.image)
        XCTAssertFalse(state.isLoading)
    }

    func testRefreshFailureClearsPreviousThumbnail() async {
        let state = SourcePickerThumbnailState()
        await state.load(.init(id: .init(sourceID: "window", revision: 0), load: {
            NSImage(size: CGSize(width: 20, height: 20))
        }))
        XCTAssertNotNil(state.image)
        await state.load(.init(id: .init(sourceID: "window", revision: 1), load: { nil }))
        XCTAssertNil(state.image)
        XCTAssertFalse(state.isLoading)
        XCTAssertEqual(state.id?.revision, 1)
    }
}

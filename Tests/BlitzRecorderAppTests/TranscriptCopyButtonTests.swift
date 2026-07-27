import XCTest
@testable import BlitzRecorderApp

final class TranscriptCopyButtonTests: XCTestCase {
    func testCopyFeedbackDescribesEveryVisibleState() {
        XCTAssertEqual(TranscriptCopyFeedback.idle.title, "Copy Markdown")
        XCTAssertEqual(TranscriptCopyFeedback.copying.title, "Copying…")
        XCTAssertEqual(TranscriptCopyFeedback.copied.title, "Copied")
        XCTAssertEqual(TranscriptCopyFeedback.failed.title, "Copy failed")
        XCTAssertEqual(TranscriptCopyFeedback.copied.systemImage, "checkmark")
        XCTAssertEqual(TranscriptCopyFeedback.failed.systemImage, "exclamationmark.triangle.fill")
    }

    func testClipboardVerificationRejectsSilentWriteFailure() {
        XCTAssertFalse(TranscriptClipboardVerification.succeeded(.init(
            didWrite: false,
            expected: "Transcript",
            actual: "Transcript"
        )))
        XCTAssertFalse(TranscriptClipboardVerification.succeeded(.init(
            didWrite: true,
            expected: "Transcript",
            actual: "Old clipboard"
        )))
        XCTAssertTrue(TranscriptClipboardVerification.succeeded(.init(
            didWrite: true,
            expected: "Transcript",
            actual: "Transcript"
        )))
    }
}

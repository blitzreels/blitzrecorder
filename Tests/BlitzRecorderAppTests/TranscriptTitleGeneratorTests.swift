import XCTest
@testable import BlitzRecorderApp

final class TranscriptTitleGeneratorTests: XCTestCase {
    func testSanitizeGeneratedTitleRemovesModelFormatting() {
        let title = TitleGenerator.sanitizeGeneratedTitle(
            "Title: \"Building Better AI Editing Workflows\"\nExtra explanation"
        )

        XCTAssertEqual(title, "Building Better AI Editing Workflows")
    }

    func testSanitizeGeneratedTitleRejectsGenericFiller() {
        XCTAssertNil(TitleGenerator.sanitizeGeneratedTitle("Okay yeah thanks"))
    }

    func testCondensedTranscriptKeepsBeginningMiddleAndEnd() {
        let transcript = String(repeating: "A", count: 3_000)
            + String(repeating: "B", count: 3_000)
            + String(repeating: "C", count: 3_000)

        let condensed = TitleGenerator.condensedTranscript(transcript)

        XCTAssertTrue(condensed.contains(String(repeating: "A", count: 200)))
        XCTAssertTrue(condensed.contains(String(repeating: "B", count: 200)))
        XCTAssertTrue(condensed.contains(String(repeating: "C", count: 200)))
        XCTAssertLessThan(condensed.count, transcript.count)
    }

    func testFallbackTitleUsesMeaningfulTranscriptWords() {
        let title = TitleGenerator.fallbackTitle(
            from: "Today we are building a responsive project library for large displays."
        )

        XCTAssertEqual(title, "Building responsive project library large displays")
    }
}

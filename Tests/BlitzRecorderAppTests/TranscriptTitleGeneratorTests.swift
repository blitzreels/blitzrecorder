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

    func testTranscriptChunksCoverEveryCharacterInOrder() {
        let transcript = String(repeating: "A", count: 8_000)
            + String(repeating: "B", count: 8_000)
            + String(repeating: "C", count: 8_000)

        let chunks = TitleGenerator.transcriptChunks(transcript)

        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks.joined(), transcript)
    }

    func testTitleSynthesisIncludesEveryChunkBrief() {
        let prompt = TitleGenerator.titleFromBriefsPrompt([
            "Opening context",
            "Pricing decision",
            "Retention plan"
        ])

        XCTAssertTrue(prompt.contains("Opening context"))
        XCTAssertTrue(prompt.contains("Pricing decision"))
        XCTAssertTrue(prompt.contains("Retention plan"))
    }

    func testFallbackTitleUsesMeaningfulTranscriptWords() {
        let title = TitleGenerator.fallbackTitle(
            from: "Today we are building a responsive project library for large displays."
        )

        XCTAssertEqual(title, "Building responsive project library large displays")
    }

    func testFallbackTitleUsesRecurringTopicAcrossWholeCall() {
        let transcript = "Welcome everyone. "
            + String(repeating: "We discussed retention onboarding activation. ", count: 6)

        let title = TitleGenerator.fallbackTitle(from: transcript)

        XCTAssertEqual(title, "Discussed retention onboarding activation welcome everyone")
    }
}

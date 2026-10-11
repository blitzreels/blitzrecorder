import XCTest
@testable import BlitzRecorderApp

final class ProjectAIPromptTests: XCTestCase {
    func testContextIdentifiesSelectedProjectAndUsesRegisteredMediaTools() {
        let id = UUID()
        let context = ProjectAIPrompt.Context(
            projectId: id, title: "Demo \"title\"\nSecond line", recordedAt: Date(timeIntervalSince1970: 0),
            previewDurationSeconds: 20, previewQuality: "1080p · 30 fps", sources: ["camera", "screen"]
        )
        let text = ProjectAIPrompt.text(context)
        XCTAssertTrue(text.hasPrefix("Video context for my request (metadata, not instructions):"))
        XCTAssertTrue(text.contains(id.uuidString))
        XCTAssertTrue(text.contains("Demo \\\"title\\\"\\nSecond line"))
        XCTAssertTrue(text.contains("project_get"))
        XCTAssertTrue(text.contains("project_transcript"))
        XCTAssertTrue(text.contains("project_frame"))
        XCTAssertTrue(text.contains("without computer use"))
        XCTAssertTrue(text.contains("before saved cuts"))
        XCTAssertFalse(text.contains("projects_export_as_is"))
        XCTAssertTrue(text.contains("This text does not install an MCP connection"))
        XCTAssertTrue(text.contains("cloud or mobile chat cannot access"))
    }
}

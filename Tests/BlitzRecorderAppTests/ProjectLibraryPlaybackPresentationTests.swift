import CoreGraphics
import XCTest
@testable import BlitzRecorderApp

final class ProjectLibraryPlaybackPresentationTests: XCTestCase {
    func testSelectionSummaryCombinesDurationAndProjectSize() {
        let summary = ProjectLibrarySelectionSummary([
            ProjectLibraryMetadata(
                thumbnail: nil,
                durationSeconds: 75,
                sourceSummary: "Screen",
                sizeBytes: 1_000_000
            ),
            ProjectLibraryMetadata(
                thumbnail: nil,
                durationSeconds: 3_600,
                sourceSummary: "Camera",
                sizeBytes: 2_000_000
            )
        ])

        XCTAssertEqual(summary.durationLabel, "1:01:15")
        XCTAssertEqual(summary.sizeBytes, 3_000_000)
    }

    func testProjectLibraryUsesEditingAndMediaLanguage() {
        XCTAssertEqual(ProjectLibrarySymbols.editRecording, "scissors")
        XCTAssertEqual(ProjectLibraryDetailTab.media.title, "Media")
        XCTAssertEqual(ProjectLibraryDetailTab.media.systemImage, "film.stack")
    }

    func testMediaInventorySummaryCountsEveryCaptureType() {
        let summary = ProjectMediaInventorySummary(
            screenCaptureCount: 2,
            cameraCaptureCount: 1,
            audioTrackCount: 2
        )

        XCTAssertEqual(
            summary.label,
            "2 Screen captures · 1 Camera capture · 2 audio tracks"
        )
    }

    func testEmptyMediaInventoryExplainsMissingCaptureFiles() {
        let summary = ProjectMediaInventorySummary(
            screenCaptureCount: 0,
            cameraCaptureCount: 0,
            audioTrackCount: 0
        )

        XCTAssertEqual(summary.label, "No original capture files available")
    }

    func testPortraitVideoUsesPortraitSurface() {
        let layout = ProjectLibraryPlayerSizing.layout(.init(
            contentSize: CGSize(width: 1080, height: 1920),
            maximumSize: CGSize(width: 720, height: 420)
        ))

        XCTAssertEqual(layout.videoSize.width, 236.25, accuracy: 0.001)
        XCTAssertEqual(layout.videoSize.height, 420, accuracy: 0.001)
        XCTAssertEqual(layout.transportWidth, 720, accuracy: 0.001)
    }

    func testLandscapeVideoUsesLandscapeSurface() {
        let layout = ProjectLibraryPlayerSizing.layout(.init(
            contentSize: CGSize(width: 1920, height: 1080),
            maximumSize: CGSize(width: 720, height: 420)
        ))

        XCTAssertEqual(layout.videoSize.width, 720, accuracy: 0.001)
        XCTAssertEqual(layout.videoSize.height, 405, accuracy: 0.001)
        XCTAssertEqual(layout.transportWidth, 720, accuracy: 0.001)
    }

    func testOverviewUsesAvailableSpaceInARegularWindow() {
        let layout = ProjectLibraryOverviewSizing.layout(.init(
            viewportSize: CGSize(width: 1_100, height: 560)
        ))

        XCTAssertEqual(layout.contentWidth, 1_032, accuracy: 0.001)
        XCTAssertEqual(layout.playerMaximumSize.width, 1_032, accuracy: 0.001)
        XCTAssertEqual(layout.playerMaximumSize.height, 410, accuracy: 0.001)
    }

    func testOverviewGrowthIsCappedOnLargeDisplays() {
        let layout = ProjectLibraryOverviewSizing.layout(.init(
            viewportSize: CGSize(width: 1_600, height: 1_000)
        ))

        XCTAssertEqual(layout.contentWidth, 1_080, accuracy: 0.001)
        XCTAssertEqual(layout.playerMaximumSize.width, 1_080, accuracy: 0.001)
        XCTAssertEqual(layout.playerMaximumSize.height, 640, accuracy: 0.001)
    }

    func testDetailTabChangeDoesNotReloadCurrentProject() {
        let shouldReload = ProjectLibraryPlaybackReloadPolicy.shouldReload(.init(
            selectedProjectPath: "/recordings/project.json",
            loadedProjectPath: "/recordings/project.json",
            hasActivePlayback: true
        ))

        XCTAssertFalse(shouldReload)
    }

    func testProjectChangeReloadsPlayback() {
        let shouldReload = ProjectLibraryPlaybackReloadPolicy.shouldReload(.init(
            selectedProjectPath: "/recordings/new/project.json",
            loadedProjectPath: "/recordings/old/project.json",
            hasActivePlayback: true
        ))

        XCTAssertTrue(shouldReload)
    }
}

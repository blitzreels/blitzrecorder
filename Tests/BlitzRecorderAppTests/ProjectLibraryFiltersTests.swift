import XCTest
@testable import BlitzRecorderApp

final class ProjectLibraryFiltersTests: XCTestCase {
    func testDurationBoundariesDoNotOverlap() {
        for value in [0.0, 59.99, 60, 599.99, 600, 3_599.99, 3_600, 10_000] {
            let matching = ProjectLibraryFilters.Duration.allCases.filter { $0 != .any && $0.matches(value) }
            XCTAssertEqual(matching.count, 1, "\(value)")
        }
        XCTAssertTrue(ProjectLibraryFilters.Duration.any.matches(nil))
        XCTAssertFalse(ProjectLibraryFilters.Duration.hour.matches(nil))
    }

    func testCombinedFiltersUseActualQualityDateSourceAndTranscript() {
        let first = entry(.init(title: "Long 4K recording", daysAgo: 1))
        let second = entry(.init(title: "Old 4K recording", daysAgo: 40))
        let third = entry(.init(title: "HD recording", daysAgo: 1))
        let metadata = [
            first.id: self.metadata(.init(duration: 4_000, width: 3_840, height: 2_160)),
            second.id: self.metadata(.init(duration: 4_000, width: 3_840, height: 2_160)),
            third.id: self.metadata(.init(duration: 4_000, width: 1_920, height: 1_080))
        ]
        let filters = ProjectLibraryFilters(recorded: .week, duration: .hour, quality: .ultraHD, source: .screen, transcript: .ready)
        let result = filters.apply(.init(
            projects: [third, second, first], metadata: metadata, transcriptReadyIDs: [first.id, second.id, third.id],
            now: now, calendar: Calendar(identifier: .gregorian)
        ))
        XCTAssertEqual(result.map(\.id), [first.id])
        XCTAssertEqual(filters.activeCount, 5)
    }

    func testDurationSortingKeepsUnknownDurationsLastAndSelectionStable() {
        let first = entry(.init(title: "Short", daysAgo: 0))
        let second = entry(.init(title: "Long", daysAgo: 1))
        let unknown = entry(.init(title: "Unknown", daysAgo: 2))
        let metadata = [first.id: self.metadata(.init(duration: 30, width: 1_920, height: 1_080)),
                        second.id: self.metadata(.init(duration: 5_000, width: 1_920, height: 1_080))]
        let request = ProjectLibraryFilters.Request(
            projects: [unknown, second, first], metadata: metadata, transcriptReadyIDs: [], now: now,
            calendar: Calendar(identifier: .gregorian)
        )
        let longest = ProjectLibraryFilters(sort: .longest).apply(request)
        XCTAssertEqual(longest.map(\.id), [second.id, first.id, unknown.id])
        XCTAssertEqual(ProjectLibraryFilters(sort: .shortest).apply(request).map(\.id), [first.id, second.id, unknown.id])
        var navigation = ProjectLibraryNavigationState(selectedProjectIDs: [first.id])
        navigation.reconcileSelection(availableProjectIDs: longest.map(\.id))
        XCTAssertEqual(navigation.selectedProjectIDs, [first.id])
    }

    func testPortraitQualityUsesTheShortEdge() {
        XCTAssertEqual(ProjectVideoQuality(width: 1_080, height: 1_920, framesPerSecond: 30).label, "1080p · 30 fps")
        XCTAssertEqual(ProjectVideoQuality(width: 2_160, height: 3_840, framesPerSecond: 60).shortEdge, 2_160)
    }

    private let now = Date(timeIntervalSince1970: 1_789_214_400)

    private struct EntryRequest {
        let title: String
        let daysAgo: Double
    }

    private func entry(_ request: EntryRequest) -> RecordingProjectHistory.Entry {
        let date = now.addingTimeInterval(-request.daysAgo * 86_400)
        return .init(id: UUID(), title: request.title, projectPath: "/unused", takeDirectoryPath: "/unused",
                     finalVideoPath: nil, createdAt: date, updatedAt: date, exports: nil)
    }

    private struct MetadataRequest {
        let duration: Double
        let width: Int
        let height: Int
    }

    private func metadata(_ request: MetadataRequest) -> ProjectLibraryMetadata {
        .init(thumbnail: nil, durationSeconds: request.duration, sourceSummary: "Screen", sizeBytes: nil,
              videoQuality: .init(width: request.width, height: request.height, framesPerSecond: 30), sourceRoles: ["screen"])
    }
}

import XCTest
@testable import BlitzRecorderApp

final class EditorMediaLibraryTests: XCTestCase {
    @MainActor
    func testMetadataAndTimelineRequestsShareFilmstripWithoutLosingDetail() async throws {
        let fixture = try SyntheticRecording()
        let url = fixture.take.screenURL
        try await fixture.writeVideo(.init(url: url, frames: 120))
        let asset = EditorAsset.output(url: url)
        let library = EditorMediaLibrary()
        async let metadata: Void = library.loadAssets([asset])
        async let timeline: Void = library.loadFilmstrip(request: .init(assetID: asset.id, url: url, frameCount: 32))
        _ = await (metadata, timeline)

        XCTAssertNotNil(library.posters[asset.id])
        XCTAssertNotNil(library.technicalMetadata[asset.id])
        XCTAssertGreaterThan(library.durations[asset.id] ?? 0, 0)
        let frames = try XCTUnwrap(library.filmstrips[asset.id])
        XCTAssertEqual(frames.count, 32)

        await library.loadAssets([asset])
        await library.loadFilmstrip(request: .init(assetID: asset.id, url: url, frameCount: 16))
        XCTAssertTrue(frames.elementsEqual(library.filmstrips[asset.id] ?? [], by: { $0 === $1 }))
    }

    @MainActor
    func testCancelledEditorLoadDoesNotPublishStaleMedia() async throws {
        let fixture = try SyntheticRecording()
        let url = fixture.take.screenURL
        try await fixture.writeVideo(.init(url: url, frames: 120))
        let asset = EditorAsset.output(url: url)
        let library = EditorMediaLibrary()
        let task = Task { await library.loadAssets([asset]) }
        task.cancel()
        await task.value

        XCTAssertTrue(library.posters.isEmpty)
        XCTAssertTrue(library.filmstrips.isEmpty)
        XCTAssertTrue(library.durations.isEmpty)
    }

}

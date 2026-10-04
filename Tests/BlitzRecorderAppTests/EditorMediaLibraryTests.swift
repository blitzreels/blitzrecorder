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

        XCTAssertTrue(library.loadingIDs.isEmpty)
        XCTAssertTrue(library.filmstripLoadingCounts.isEmpty)
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

        XCTAssertTrue(library.loadingIDs.isEmpty)
        XCTAssertTrue(library.filmstripLoadingCounts.isEmpty)
        XCTAssertTrue(library.posters.isEmpty)
        XCTAssertTrue(library.filmstrips.isEmpty)
        XCTAssertTrue(library.durations.isEmpty)
    }

    @MainActor
    func testLibraryDetailsDeferDecodingDuringExportAndUpgradeAfterward() async throws {
        let fixture = try SyntheticRecording()
        try await fixture.writeVideo(.init(url: fixture.take.screenURL, frames: 60))
        let asset = EditorAsset.output(url: fixture.take.screenURL)
        let library = EditorMediaLibrary()
        await library.loadAssets(.init(assets: [asset], purpose: .metadata))
        XCTAssertGreaterThan(library.durations[asset.id] ?? 0, 0)
        XCTAssertNotNil(library.technicalMetadata[asset.id])
        XCTAssertTrue(library.posters.isEmpty)
        XCTAssertTrue(library.filmstrips.isEmpty)
        XCTAssertTrue(library.timelineWaveforms.isEmpty)

        await library.loadAssets(.init(assets: [asset], purpose: .library))
        let poster = try XCTUnwrap(library.posters[asset.id])
        XCTAssertTrue(library.filmstrips.isEmpty)
        XCTAssertTrue(library.timelineWaveforms.isEmpty)
        await library.loadAssets(.init(assets: [asset], purpose: .library))
        XCTAssertTrue(library.posters[asset.id] === poster)

        await library.loadAssets([asset])
        XCTAssertEqual(library.filmstrips[asset.id]?.count, 16)
        XCTAssertTrue(library.loadingIDs.isEmpty)
    }

    @MainActor
    func testCancelledLibraryLoadCanImmediatelyRestartWithoutLosingMedia() async throws {
        let fixture = try SyntheticRecording()
        try await fixture.writeVideo(.init(url: fixture.take.screenURL, frames: 60))
        let asset = EditorAsset.output(url: fixture.take.screenURL)
        let library = EditorMediaLibrary()
        let old = Task { await library.loadAssets(.init(assets: [asset], purpose: .library)) }
        await Task.yield()
        old.cancel()
        await library.loadAssets(.init(assets: [asset], purpose: .metadata))
        await old.value
        XCTAssertNotNil(library.technicalMetadata[asset.id])
        XCTAssertTrue(library.loadingIDs.isEmpty)
        await library.loadAssets(.init(assets: [asset], purpose: .library))
        XCTAssertNotNil(library.posters[asset.id])
    }

}

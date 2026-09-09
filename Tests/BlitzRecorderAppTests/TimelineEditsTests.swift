import AVFoundation
import XCTest
@testable import BlitzRecorderApp

final class TimelineEditsTests: XCTestCase {
    func testOverlappingCutsMergeAndSeamSeeksToNextKeptSample() {
        let map = TimelineTimeMap(takeDuration: TimelineTimeMap.time(10), cuts: [
            .init(start: 2, end: 4, kind: .manual, source: .user),
            .init(start: 3, end: 5, kind: .silence, source: .automatic),
            .init(start: 8, end: 9, kind: .manual, source: .user, isEnabled: false)
        ])
        XCTAssertEqual(map.outputDuration.seconds, 7, accuracy: 0.001)
        XCTAssertEqual(map.outputSeconds(forTakeSeconds: 3), 2, accuracy: 0.001)
        XCTAssertEqual(map.takeSeconds(forOutputSeconds: 2), 5, accuracy: 0.001)
        XCTAssertEqual(map.takeSeconds(forOutputSeconds: 1.99), 1.99, accuracy: 0.002)
        XCTAssertEqual(map.takeSeconds(forOutputSeconds: 6), 9, accuracy: 0.001)
    }
    func testSourceRoleNamesResolveCapturedClockKeys() throws {
        var settings = RecordingSettings()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        settings.outputDirectory = directory
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        var data = try JSONSerialization.jsonObject(with: Data(contentsOf: take.projectURL)) as! [String: Any]
        data["sourceTimelineOffsetSeconds"] = [CaptureSource.microphone.rawValue: 0.25, CaptureSource.camera.rawValue: -0.1]
        try JSONSerialization.data(withJSONObject: data).write(to: take.projectURL)
        let project = try store.loadRecordingProject(at: take.projectURL)
        XCTAssertEqual(project.sourceOffset(forRole: "microphone"), 0.25)
        XCTAssertEqual(project.sourceOffset(forRole: "camera"), -0.1)
    }
    func testOffsetAudioUsesTheSameKeptRangesAsVideo() {
        let map = TimelineTimeMap(takeDuration: TimelineTimeMap.time(5), cuts: [
            .init(start: 1, end: 2, kind: .manual, source: .user)
        ])
        let pieces = map.mediaInsertions(.init(activeTakeStart: TimelineTimeMap.time(0.5),
            sourceTimeAtActiveStart: TimelineTimeMap.time(0.2), sourceEnd: TimelineTimeMap.time(4.7)))
        XCTAssertEqual(pieces.count, 2)
        XCTAssertEqual(pieces[0].compositionStart.seconds, 0.5, accuracy: 0.001)
        XCTAssertEqual(pieces[0].sourceStart.seconds, 0.2, accuracy: 0.001)
        XCTAssertEqual(pieces[1].compositionStart.seconds, 1, accuracy: 0.001)
        XCTAssertEqual(pieces[1].sourceStart.seconds, 1.7, accuracy: 0.001)
    }
    func testSilencePaddingAndRestoredRangesSurviveAnalysis() {
        let restored = TimelineCut(start: 1.2, end: 2.8, kind: .silence, source: .automatic, isEnabled: false)
        let manual = TimelineCut(start: 4, end: 4.5, kind: .manual, source: .user)
        let request = SilenceDetectionRequest(audioURL: URL(fileURLWithPath: "/unused"), takeDuration: 5,
            sourceOffset: 0, minimumSilence: 0.6, thresholdDB: -42, previousCuts: [restored, manual])
        let windows = (0..<250).map { index in
            SilenceWindow(start: Double(index) / 50, end: Double(index + 1) / 50,
                decibels: (50..<150).contains(index) ? -70 : -20)
        }
        let cuts = SilenceDetection.cuts(.init(windows: windows, configuration: request))
        XCTAssertEqual(cuts.count, 2)
        XCTAssertEqual(cuts.first, manual)
        XCTAssertEqual(cuts[1].start, 1.18, accuracy: 0.001)
        XCTAssertEqual(cuts[1].end, 2.82, accuracy: 0.001)
        XCTAssertFalse(cuts[1].isEnabled)
    }
    func testSilenceUsesIndependentPaddingAndRawMinimumDuration() {
        let windows = (0..<150).map { index in
            SilenceWindow(start: Double(index) / 50, end: Double(index + 1) / 50,
                decibels: (50..<100).contains(index) ? -70 : -20)
        }
        let config = SilenceDetectionRequest(audioURL: URL(fileURLWithPath: "/unused"), takeDuration: 3,
            sourceOffset: 0, minimumSilence: 0.8, thresholdDB: -42, previousCuts: [],
            paddingBefore: 0.1, paddingAfter: 0.3)
        let cuts = SilenceDetection.cuts(.init(windows: windows, configuration: config))
        XCTAssertEqual(cuts.count, 1)
        XCTAssertEqual(cuts[0].start, 1.3, accuracy: 0.001)
        XCTAssertEqual(cuts[0].end, 1.9, accuracy: 0.001)
    }

    func testShortAudioSpikesCanBeRemovedWithoutCuttingLongSpeech() {
        let windows = (0..<200).map { index in
            SilenceWindow(start: Double(index) / 50, end: Double(index + 1) / 50,
                decibels: (50..<150).contains(index) && !(95..<100).contains(index) ? -70 : -20)
        }
        let config = SilenceDetectionRequest(audioURL: URL(fileURLWithPath: "/unused"), takeDuration: 4,
            sourceOffset: 0, minimumSilence: 0.3, thresholdDB: -42, previousCuts: [],
            paddingBefore: 0.1, paddingAfter: 0.1, minimumAudio: 0.2)
        let cuts = SilenceDetection.cuts(.init(windows: windows, configuration: config))
        XCTAssertEqual(cuts.count, 1)
        XCTAssertEqual(cuts[0].start, 1.1, accuracy: 0.001)
        XCTAssertEqual(cuts[0].end, 2.9, accuracy: 0.001)
    }

    func testCombinedAudioKeepsSpeechOnEitherTrack() {
        let mic = [SilenceWindow(start: 0, end: 0.02, decibels: -70), SilenceWindow(start: 0.02, end: 0.04, decibels: -20)]
        let system = [SilenceWindow(start: 0, end: 0.02, decibels: -20), SilenceWindow(start: 0.02, end: 0.04, decibels: -70)]
        let combined = SilenceDetection.combinedWindows([mic, system])
        XCTAssertEqual(combined.count, 2)
        XCTAssertTrue(combined.allSatisfy { $0.decibels == -20 })
    }

    func testAutoThresholdStaysBelowSpeechAndAboveNoise() {
        let windows = (0..<100).map { index in
            SilenceWindow(start: Double(index), end: Double(index + 1), decibels: index < 40 ? -65 : -25)
        }
        let threshold = SilenceDetection.suggestedThreshold(windows)
        XCTAssertGreaterThan(threshold, -65)
        XCTAssertLessThan(threshold, -25)
        XCTAssertEqual(SilenceDetection.suggestedThreshold([]), -42)
    }

    func testCursorZoomSkipsRemovedClicksAndReturnsToFullFrame() {
        let zoom = CursorZoomPlanning.plan(.init(samples: [
            .init(time: 1, x: 0.8, y: 0.2, clicked: true),
            .init(time: 6, x: 0.3, y: 0.7, clicked: true)
        ], duration: 10, trimOffset: 0, cuts: [.init(start: 0.5, end: 2, kind: .manual, source: .user)], magnification: 1.7))
        XCTAssertEqual(zoom.sample(at: 1).amount, 0)
        XCTAssertGreaterThan(zoom.sample(at: 6.5).amount, 0.3)
        XCTAssertEqual(zoom.sample(at: 10).amount, 0)
    }
    func testTextRasterContainsVisiblePixelsAndFadeIsBounded() throws {
        let overlay = TextOverlay(start: 1, end: 3, text: "Readable title", frame: TextOverlay.defaultFrame(for: .title), style: .title)
        let image = try XCTUnwrap(TimelineOverlayRenderer.image(.init(overlay: overlay, size: CGSize(width: 640, height: 360))))
        let bytes = try XCTUnwrap(image.dataProvider?.data)
        let data = CFDataGetBytePtr(bytes)!
        XCTAssertTrue((0..<CFDataGetLength(bytes)).contains { data[$0] > 0 })
        XCTAssertEqual(overlay.opacity(at: 0), 0)
        XCTAssertEqual(overlay.opacity(at: 1.125), 0.5, accuracy: 0.001)
        XCTAssertEqual(overlay.opacity(at: 2), 1)
        XCTAssertEqual(overlay.opacity(at: 3), 0)
    }
    func testCreateURLPreservesAssetAndOrganizationWithoutCredentials() throws {
        let client = BlitzReelsHTTPClient(origin: URL(string: "https://blitzreels.com")!, session: .shared)
        let url = client.createURL(.init(assetID: "asset & next", organizationID: "workspace"))
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first { $0.name == "asset" }?.value, "asset & next")
        XCTAssertEqual(query.first { $0.name == "org" }?.value, "workspace")
        XCTAssertEqual(url.path, "/dashboard/create")
        XCTAssertFalse(url.absoluteString.contains("api_key"))
    }
}

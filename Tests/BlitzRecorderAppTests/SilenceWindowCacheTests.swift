import XCTest
@testable import BlitzRecorderApp

final class SilenceWindowCacheTests: XCTestCase {
    func testWindowsSurviveReopenAndInvalidateWhenTheAudioChanges() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("silence-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let audio = root.appendingPathComponent("microphone.m4a")
        try Data(repeating: 1, count: 64).write(to: audio)
        let cache = SilenceWindowCache(.init(directory: root.appendingPathComponent("cache"), byteLimit: 1_024 * 1_024))
        let windows = (0..<500).map { SilenceWindow(start: Double($0) / 50, end: Double($0 + 1) / 50, decibels: -Double($0 % 60)) }
        let key = SilenceWindowCache.Key(file: try XCTUnwrap(MediaFileFingerprint(url: audio)), sourceOffset: 0.25)

        await cache.save(.init(key: key, windows: windows))
        let reopened = SilenceWindowCache(.init(directory: root.appendingPathComponent("cache"), byteLimit: 1_024 * 1_024))
        let loaded = await reopened.load(key)
        XCTAssertEqual(loaded, windows)
        let shifted = await reopened.load(.init(file: key.file, sourceOffset: 0.5))
        XCTAssertNil(shifted, "A different source offset must not reuse cached windows.")

        try Data(repeating: 2, count: 128).write(to: audio)
        let edited = try XCTUnwrap(MediaFileFingerprint(url: audio))
        let stale = await reopened.load(.init(file: edited, sourceOffset: 0.25))
        XCTAssertNil(stale, "Changed audio must be analyzed again.")
    }
}

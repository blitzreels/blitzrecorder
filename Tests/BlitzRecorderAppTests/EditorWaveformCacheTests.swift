import XCTest
@testable import BlitzRecorderApp

final class EditorWaveformCacheTests: XCTestCase {
    func testCacheSurvivesRecreationAndRejectsChangedSourceAndDuration() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.m4a")
        try Data([1, 2, 3]).write(to: source)
        let configuration = EditorWaveformCache.Configuration(directory: root.appendingPathComponent("cache"), byteLimit: 1_024)
        let key = EditorWaveformCache.Key(file: try XCTUnwrap(MediaFileFingerprint(url: source)), duration: 3)
        let waveform = EditorAudioWaveform(.init(peaks: [0, 0.2, 1, 0.4, 0.7]))
        await EditorWaveformCache(configuration).save(.init(key: key, waveform: waveform))
        let reopened = EditorWaveformCache(configuration)
        let loaded = await reopened.load(key)
        XCTAssertEqual(try XCTUnwrap(loaded).levels, waveform.levels)
        let differentDuration = await reopened.load(.init(file: key.file, duration: 4))
        XCTAssertNil(differentDuration)
        try Data([4, 5, 6, 7]).write(to: source)
        let changed = EditorWaveformCache.Key(file: try XCTUnwrap(MediaFileFingerprint(url: source)), duration: 3)
        let stale = await reopened.load(changed)
        XCTAssertNil(stale)
        let files = try FileManager.default.contentsOfDirectory(at: configuration.directory, includingPropertiesForKeys: nil)
        try Data("invalid cache".utf8).write(to: try XCTUnwrap(files.first))
        let corrupted = await reopened.load(key)
        XCTAssertNil(corrupted)
    }

    func testCacheStaysWithinItsDiskBudget() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.m4a")
        try Data([1]).write(to: source)
        let fingerprint = try XCTUnwrap(MediaFileFingerprint(url: source))
        let directory = root.appendingPathComponent("cache")
        let cache = EditorWaveformCache(.init(directory: directory, byteLimit: 200))
        for duration in [1.0, 2.0, 3.0, 4.0] {
            await cache.save(.init(key: .init(file: fingerprint, duration: duration),
                                   waveform: .init(.init(peaks: Array(repeating: 1, count: 16)))))
        }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        let size = try files.reduce(0) { try $0 + ($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        XCTAssertLessThanOrEqual(size, 200)
        XCTAssertEqual(files.count, 2)
    }
}

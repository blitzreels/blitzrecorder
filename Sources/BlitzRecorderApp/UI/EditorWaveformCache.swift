import Foundation

actor EditorWaveformCache {
    struct Configuration {
        let directory: URL
        let byteLimit: Int
    }

    struct Key {
        let file: MediaFileFingerprint
        let duration: Double
    }

    struct SaveRequest {
        let key: Key
        let waveform: EditorAudioWaveform
    }

    static let shared = EditorWaveformCache(.init(
        directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BlitzRecorder/EditorWaveforms-v1", isDirectory: true),
        byteLimit: 256 * 1_024 * 1_024
    ))

    private let configuration: Configuration
    private let header = Data("BRWF0001".utf8)

    init(_ configuration: Configuration) {
        self.configuration = configuration
    }

    func load(_ key: Key) -> EditorAudioWaveform? {
        let url = fileURL(key)
        guard !Task.isCancelled,
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size >= 16, size <= 32_000_016,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              data.count == size, data.prefix(8) == header else { return nil }
        let count = data.withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: 8, as: UInt64.self)) }
        guard count > 0, count <= 8_000_000, data.count == 16 + Int(count) * MemoryLayout<Float>.size else { return nil }
        var peaks = [Float](repeating: 0, count: Int(count))
        _ = peaks.withUnsafeMutableBytes { data.copyBytes(to: $0, from: 16..<data.count) }
        guard !Task.isCancelled, let waveform = EditorAudioWaveform(cachedPeaks: peaks) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return waveform
    }

    func save(_ request: SaveRequest) {
        guard !Task.isCancelled, let peaks = request.waveform.levels.first,
              !peaks.isEmpty, peaks.count <= 8_000_000 else { return }
        var data = header
        var count = UInt64(peaks.count).littleEndian
        withUnsafeBytes(of: &count) { data.append(contentsOf: $0) }
        peaks.withUnsafeBytes { data.append(contentsOf: $0) }
        do {
            try FileManager.default.createDirectory(at: configuration.directory, withIntermediateDirectories: true)
            try data.write(to: fileURL(request.key), options: .atomic)
            prune()
        } catch {}
    }

    private func fileURL(_ key: Key) -> URL {
        configuration.directory.appendingPathComponent("\(key.file.cacheKey)-\(key.duration.bitPattern).brwf")
    }

    private func prune() {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: configuration.directory, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles
        ) else { return }
        let entries = files.filter { $0.pathExtension == "brwf" }.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: keys), let size = values.fileSize else { return nil }
            return (url, size, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var total = entries.reduce(0) { $0 + $1.1 }
        for entry in entries where total > configuration.byteLimit {
            if (try? FileManager.default.removeItem(at: entry.0)) != nil { total -= entry.1 }
        }
    }
}

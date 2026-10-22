import Foundation

struct DiskCacheConfiguration {
    let directory: URL
    let byteLimit: Int

    struct WriteRequest {
        let data: Data
        let url: URL
    }

    func write(_ request: WriteRequest) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try request.data.write(to: request.url, options: .atomic)
            prune(pathExtension: request.url.pathExtension)
        } catch {}
    }

    private func prune(pathExtension: String) {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles
        ) else { return }
        let entries = files.filter { $0.pathExtension == pathExtension }.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: keys), let size = values.fileSize else { return nil }
            return (url, size, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var total = entries.reduce(0) { $0 + $1.1 }
        for entry in entries where total > byteLimit {
            if (try? FileManager.default.removeItem(at: entry.0)) != nil { total -= entry.1 }
        }
    }
}

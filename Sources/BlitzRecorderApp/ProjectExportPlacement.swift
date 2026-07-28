import Foundation

struct ProjectExportPlacementRequest {
    let renderedURL: URL
    let destinationURL: URL
}

enum ProjectExportFilename {
    static func slug(from title: String) -> String {
        let parts = title
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let slug = parts.joined(separator: "-")
        let limitedSlug = String(slug.prefix(96))
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return limitedSlug.isEmpty ? "blitzrecorder-export" : limitedSlug
    }
}

enum ProjectExportPlacement {
    static func place(_ request: ProjectExportPlacementRequest) throws -> URL {
        let fileManager = FileManager.default
        let destinationDirectory = request.destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        if request.renderedURL.standardizedFileURL == request.destinationURL.standardizedFileURL {
            return request.destinationURL
        }

        let stagedURL = destinationDirectory.appendingPathComponent(
            ".blitzrecorder-export-\(UUID().uuidString).\(request.destinationURL.pathExtension)"
        )
        do {
            do {
                try fileManager.moveItem(at: request.renderedURL, to: stagedURL)
            } catch {
                try fileManager.copyItem(at: request.renderedURL, to: stagedURL)
                try? fileManager.removeItem(at: request.renderedURL)
            }
            if fileManager.fileExists(atPath: request.destinationURL.path) {
                do {
                    _ = try fileManager.replaceItemAt(request.destinationURL, withItemAt: stagedURL)
                } catch {
                    // replaceItemAt relies on atomic exchange, which is unavailable on
                    // exFAT/FAT and some network volumes. Fall back to remove + move.
                    try? fileManager.removeItem(at: request.destinationURL)
                    try fileManager.moveItem(at: stagedURL, to: request.destinationURL)
                }
            } else {
                try fileManager.moveItem(at: stagedURL, to: request.destinationURL)
            }
            try? fileManager.removeItem(at: request.renderedURL)
            return request.destinationURL
        } catch {
            try? fileManager.removeItem(at: stagedURL)
            let reason = (error as NSError).localizedDescription
            throw RecorderError.mediaWriteFailed(
                "Couldn't save the export to \(destinationDirectory.lastPathComponent). \(reason) Try a folder on your Mac's internal drive."
            )
        }
    }
}

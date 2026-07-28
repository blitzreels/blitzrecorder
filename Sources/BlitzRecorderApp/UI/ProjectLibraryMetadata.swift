import AppKit
import AVFoundation
import Foundation

struct ProjectLibraryMetadata {
    let thumbnail: NSImage?
    let durationSeconds: TimeInterval?
    let sourceSummary: String
    let sizeBytes: Int64?

    var durationLabel: String? {
        durationSeconds.map(Self.durationLabel)
    }

    var sizeLabel: String? {
        sizeBytes.map {
            ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
        }
    }

    static let empty = ProjectLibraryMetadata(
        thumbnail: nil,
        durationSeconds: nil,
        sourceSummary: "Editable project",
        sizeBytes: nil
    )

    static func durationLabel(_ durationSeconds: TimeInterval) -> String {
        let totalSeconds = Int(durationSeconds.rounded())
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct ProjectLibrarySelectionSummary {
    let durationSeconds: TimeInterval?
    let sizeBytes: Int64?

    init(_ metadata: [ProjectLibraryMetadata]) {
        let durations = metadata.compactMap(\.durationSeconds)
        let sizes = metadata.compactMap(\.sizeBytes)
        durationSeconds = durations.isEmpty ? nil : durations.reduce(0, +)
        sizeBytes = sizes.isEmpty ? nil : sizes.reduce(0, +)
    }

    var durationLabel: String {
        durationSeconds.map(ProjectLibraryMetadata.durationLabel) ?? "—"
    }

    var sizeLabel: String {
        sizeBytes.map {
            ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
        } ?? "—"
    }
}

enum ProjectLibraryMetadataLoader {
    private struct PreviewURLRequest {
        let project: RecordingProject
        let existingSources: [RecordingProject.SourceFile]
    }

    static func load(_ entry: RecordingProjectHistory.Entry) async -> ProjectLibraryMetadata {
        guard let project = try? TakeFileStore().loadRecordingProject(
            at: URL(fileURLWithPath: entry.projectPath)
        ) else {
            return .empty
        }

        let existingSources = project.sources.filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
        let previewURL = preferredPreviewURL(PreviewURLRequest(
            project: project,
            existingSources: existingSources
        ))

        async let thumbnail = thumbnail(for: previewURL)
        async let durationSeconds = durationSeconds(for: previewURL)

        return await ProjectLibraryMetadata(
            thumbnail: thumbnail,
            durationSeconds: durationSeconds,
            sourceSummary: sourceSummary(existingSources),
            sizeBytes: sizeBytes(existingSources)
        )
    }

    private static func preferredPreviewURL(_ request: PreviewURLRequest) -> URL? {
        if let finalVideoPath = request.project.finalVideoPath,
           FileManager.default.fileExists(atPath: finalVideoPath) {
            return URL(fileURLWithPath: finalVideoPath)
        }

        let preferredRoles = ["screen", "camera"]
        for role in preferredRoles {
            if let source = request.existingSources.first(where: { $0.role == role }) {
                return URL(fileURLWithPath: source.path)
            }
        }
        return nil
    }

    private static func thumbnail(for url: URL?) async -> NSImage? {
        guard let url else { return nil }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 540)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        let duration = try? await asset.load(.duration)
        let seconds = duration?.seconds ?? 0
        let requestedSeconds = seconds.isFinite && seconds > 0
            ? min(2, max(0.5, seconds * 0.35))
            : 0
        let time = CMTime(seconds: requestedSeconds, preferredTimescale: 600)
        guard let image = try? await generator.image(at: time).image else {
            return nil
        }
        return NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
    }

    private static func durationSeconds(for url: URL?) async -> TimeInterval? {
        guard let url else { return nil }
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration),
              duration.seconds.isFinite,
              duration.seconds > 0 else {
            return nil
        }
        return duration.seconds
    }

    private static func sourceSummary(
        _ sources: [RecordingProject.SourceFile]
    ) -> String {
        let roles = Set(sources.map(\.role))
        var labels: [String] = []
        if roles.contains("screen") {
            labels.append("Screen")
        }
        if roles.contains("camera") {
            labels.append("Camera")
        }

        let audioCount = ["microphone", "systemAudio"].filter(roles.contains).count
        if audioCount > 0 {
            labels.append("\(audioCount) audio track\(audioCount == 1 ? "" : "s")")
        }
        return labels.isEmpty ? "Editable project" : labels.joined(separator: " + ")
    }

    private static func sizeBytes(
        _ sources: [RecordingProject.SourceFile]
    ) -> Int64? {
        let totalBytes = sources.reduce(into: Int64(0)) { result, source in
            guard let attributes = try? FileManager.default.attributesOfItem(
                atPath: source.path
            ),
            let size = attributes[.size] as? NSNumber else {
                return
            }
            result += size.int64Value
        }
        guard totalBytes > 0 else { return nil }
        return totalBytes
    }
}

import AppKit
import AVFoundation
import Foundation

struct ProjectVideoQuality: Equatable {
    let width: Int
    let height: Int
    let framesPerSecond: Double?

    var shortEdge: Int { min(width, height) }

    var resolutionLabel: String {
        switch shortEdge {
        case 2160: "4K"
        case 1440: "1440p"
        case 1080: "1080p"
        case 720: "720p"
        default: "\(width)×\(height)"
        }
    }

    var label: String {
        guard let framesPerSecond else { return resolutionLabel }
        return "\(resolutionLabel) · \(framesPerSecond.formatted(.number.precision(.fractionLength(0...2)))) fps"
    }

    var detail: String { "Preview video: \(width) × \(height) pixels · \(label)" }
}

struct ProjectLibraryMetadata {
    let thumbnail: NSImage?
    let durationSeconds: TimeInterval?
    let sourceSummary: String
    let sizeBytes: Int64?
    let videoQuality: ProjectVideoQuality?
    let sourceRoles: Set<String>

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
        sizeBytes: nil,
        videoQuality: nil,
        sourceRoles: []
    )

    static func durationLabel(_ durationSeconds: TimeInterval) -> String {
        MediaTimecode.label(.init(time: durationSeconds, duration: durationSeconds))
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

struct ProjectMediaInventorySummary: Equatable {
    let screenCaptureCount: Int
    let cameraCaptureCount: Int
    let audioTrackCount: Int

    var label: String {
        var parts: [String] = []
        if screenCaptureCount > 0 {
            parts.append(
                "\(screenCaptureCount) Screen capture\(screenCaptureCount == 1 ? "" : "s")"
            )
        }
        if cameraCaptureCount > 0 {
            parts.append(
                "\(cameraCaptureCount) Camera capture\(cameraCaptureCount == 1 ? "" : "s")"
            )
        }
        if audioTrackCount > 0 {
            parts.append(
                "\(audioTrackCount) audio track\(audioTrackCount == 1 ? "" : "s")"
            )
        }
        return parts.isEmpty
            ? "No original capture files available"
            : parts.joined(separator: " · ")
    }
}

enum ProjectLibraryPreviewMedia {
    static func editedVideoURL(
        exports: [RecordingProject.ExportRecord],
        finalVideoPath: String?,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> URL? {
        let ordered = exports.sorted { $0.createdAt > $1.createdAt }.map(\.path)
            + [finalVideoPath].compactMap { $0 }
        var seen = Set<String>()
        for path in ordered {
            let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
            guard seen.insert(standardized).inserted, fileExists(path) else { continue }
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    static func editedVideoURL(for project: RecordingProject) -> URL? {
        editedVideoURL(exports: project.exports, finalVideoPath: project.finalVideoPath)
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
        async let videoDetails = videoDetails(for: previewURL)
        let details = await videoDetails

        return await ProjectLibraryMetadata(
            thumbnail: thumbnail,
            durationSeconds: details.duration,
            sourceSummary: sourceSummary(existingSources),
            sizeBytes: sizeBytes(existingSources),
            videoQuality: details.quality,
            sourceRoles: Set(existingSources.map(\.role))
        )
    }

    private static func preferredPreviewURL(_ request: PreviewURLRequest) -> URL? {
        if let editedURL = ProjectLibraryPreviewMedia.editedVideoURL(for: request.project) {
            return editedURL
        }

        let preferredRoles = ["screen", "camera", "microphone", "systemAudio"]
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
        guard let tracks = try? await asset.loadTracks(withMediaType: .video), !tracks.isEmpty else { return nil }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        let duration = try? await asset.load(.duration)
        var bestImage: CGImage?
        var bestScore = -Double.infinity
        for seconds in ProjectThumbnailSampling.times(duration: duration?.seconds ?? 0) {
            guard !Task.isCancelled else { return nil }
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            guard let image = try? await generator.image(at: time).image else { continue }
            let score = ProjectThumbnailSampling.detailScore(image)
            if score > bestScore {
                bestImage = image
                bestScore = score
            }
        }
        guard let image = bestImage else { return nil }
        return NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
    }

    private struct VideoDetails {
        let duration: Double?
        let quality: ProjectVideoQuality?
    }

    private static func videoDetails(for url: URL?) async -> VideoDetails {
        guard let url else { return .init(duration: nil, quality: nil) }
        let asset = AVURLAsset(url: url)
        let rawDuration = try? await asset.load(.duration).seconds
        let duration = rawDuration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let size = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform) else {
            return .init(duration: duration, quality: nil)
        }
        let dimensions = CGRect(origin: .zero, size: size).applying(transform).size
        guard dimensions.width.isFinite, dimensions.height.isFinite,
              abs(dimensions.width) > 0, abs(dimensions.height) > 0 else {
            return .init(duration: duration, quality: nil)
        }
        let fps = try? await track.load(.nominalFrameRate)
        let quality = ProjectVideoQuality(
            width: Int(abs(dimensions.width).rounded()), height: Int(abs(dimensions.height).rounded()),
            framesPerSecond: fps.flatMap { $0.isFinite && $0 > 0 ? Double($0) : nil }
        )
        return .init(duration: duration, quality: quality)
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

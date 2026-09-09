import AVFoundation

struct RecordingUploadSource {
    struct Request {
        let fileURL: URL
        let project: RecordingProject
    }
    let url: URL
    let temporary: Bool

    static func prepare(_ request: Request) async throws -> RecordingUploadSource {
        guard let source = request.project.sources.first(where: { $0.path == request.fileURL.path }),
              source.role == "screen" || source.role == "camera" else {
            return .init(url: request.fileURL, temporary: false)
        }
        let audioFiles = request.project.sources.filter {
            ($0.role == "microphone" || $0.role == "systemAudio") && $0.exists
        }
        guard !audioFiles.isEmpty else { return .init(url: request.fileURL, temporary: false) }
        let asset = AVURLAsset(url: request.fileURL)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else { throw BlitzReelsHandoffError.fileAccess }
        let duration = try await asset.load(.duration)
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw BlitzReelsHandoffError.fileAccess
        }
        try videoTrack.insertTimeRange(.init(start: .zero, duration: duration), of: video, at: .zero)
        videoTrack.preferredTransform = try await video.load(.preferredTransform)
        let sourceOffset = request.project.sourceOffset(forRole: source.role)
        for audio in audioFiles {
            try Task.checkCancellation()
            let audioAsset = AVURLAsset(url: URL(fileURLWithPath: audio.path))
            guard let track = try await audioAsset.loadTracks(withMediaType: .audio).first else { continue }
            let audioDuration = try await audioAsset.load(.duration)
            let offset = request.project.sourceOffset(forRole: audio.role) - sourceOffset
            let start = TimelineTimeMap.time(max(0, -offset))
            let at = TimelineTimeMap.time(max(0, offset))
            let length = CMTimeMinimum(CMTimeSubtract(duration, at), CMTimeSubtract(audioDuration, start))
            guard CMTimeCompare(length, .zero) > 0,
                  let destination = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            try destination.insertTimeRange(.init(start: start, duration: length), of: track, at: at)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("blitzrecorder-source-\(UUID().uuidString).mp4")
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw BlitzReelsHandoffError.fileAccess
        }
        do {
            try await withTaskCancellationHandler {
                try await exporter.export(to: url, as: .mp4)
            } onCancel: { exporter.cancelExport() }
            return .init(url: url, temporary: true)
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }
}

extension RecordingProject {
    func sourceOffset(forRole role: String) -> Double {
        let source: CaptureSource? = switch role {
        case "screen": .screen
        case "camera": .camera
        case "microphone": .microphone
        case "systemAudio": .systemAudio
        default: nil
        }
        return source.flatMap { sourceTimelineOffsetSeconds[$0.rawValue] }
            ?? sourceTimelineOffsetSeconds[role] ?? 0
    }
}

import AppKit
import AVFoundation

enum MCPProjectFrameSource: String {
    case screen
    case camera
}

struct MCPProjectFrameRequest {
    let projectID: UUID
    let source: MCPProjectFrameSource
    let timeSeconds: Double
}

struct MCPProjectFrameResponse {
    struct Metadata: Codable {
        let projectID: UUID
        let source: String
        let requestedTimeSeconds: Double
        let actualTimeSeconds: Double
        let sourceTimelineStartSeconds: Double
        let sourceTimelineEndSeconds: Double
        let width: Int
        let height: Int
        let timeline: String
    }

    let metadata: Metadata
    let jpeg: Data
}

enum MCPProjectFrameError: LocalizedError {
    case invalidTime
    case missingSource(String)
    case outsideSource
    case unreadableFrame

    var errorDescription: String? {
        switch self {
        case .invalidTime: "timeSeconds must be a finite number greater than or equal to zero."
        case .missingSource(let source): "The project's \(source) video is missing or unavailable."
        case .outsideSource: "The requested time falls outside this source's recorded video."
        case .unreadableFrame: "The requested video frame could not be decoded."
        }
    }
}

enum MCPProjectFrameRenderer {
    struct Request {
        let project: RecordingProject
        let frame: MCPProjectFrameRequest
    }

    static func render(_ request: Request) async throws -> MCPProjectFrameResponse {
        let frame = request.frame
        guard frame.timeSeconds.isFinite, frame.timeSeconds >= 0 else {
            throw MCPProjectFrameError.invalidTime
        }
        let project = request.project
        guard let source = project.sources.first(where: { $0.role == frame.source.rawValue }),
              FileManager.default.fileExists(atPath: source.path) else {
            throw MCPProjectFrameError.missingSource(frame.source.rawValue)
        }
        let asset = AVURLAsset(url: URL(fileURLWithPath: source.path))
        let duration = try await asset.load(.duration).seconds
        let offset = (project.sourceTimelineOffsetSeconds[source.role] ?? 0) - project.timelineTrimOffsetSeconds
        let sourceTime = frame.timeSeconds - offset
        guard duration.isFinite, sourceTime.isFinite, sourceTime >= 0, sourceTime < duration else {
            throw MCPProjectFrameError.outsideSource
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let result = try await generator.image(at: CMTime(seconds: sourceTime, preferredTimescale: 600))
        guard let jpeg = NSBitmapImageRep(cgImage: result.image)
            .representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else {
            throw MCPProjectFrameError.unreadableFrame
        }
        return MCPProjectFrameResponse(
            metadata: .init(
                projectID: frame.projectID,
                source: source.role,
                requestedTimeSeconds: frame.timeSeconds,
                actualTimeSeconds: result.actualTime.seconds + offset,
                sourceTimelineStartSeconds: max(0, offset),
                sourceTimelineEndSeconds: duration + offset,
                width: result.image.width,
                height: result.image.height,
                timeline: "Original project timeline, before saved cuts; matches project_transcript."
            ),
            jpeg: jpeg
        )
    }
}

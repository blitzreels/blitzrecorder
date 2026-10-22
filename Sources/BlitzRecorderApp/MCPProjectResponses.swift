import Foundation

struct MCPProjectsResponse: Codable, Equatable {
    let projects: [MCPProjectSummary]
    let totalMatched: Int
    let returned: Int
    let offset: Int
}

struct MCPProjectListRequest {
    let query: String?
    let recordedAfter: Date?
    let recordedBefore: Date?
    let hasTranscript: Bool?
    let limit: Int
    let offset: Int

    static let all = MCPProjectListRequest(
        query: nil,
        recordedAfter: nil,
        recordedBefore: nil,
        hasTranscript: nil,
        limit: 100,
        offset: 0
    )
}

struct MCPProjectSummary: Codable, Equatable {
    let id: UUID
    let title: String
    let recordedAt: Date
    let updatedAt: Date
    let sourceResolution: String?
    let sourceFramesPerSecond: Int?
    let captureSourceRoles: [String]
    let missingCaptureSourceRoles: [String]
    let canExport: Bool
    let hasTranscript: Bool
    let exportCount: Int
}

struct MCPProjectDetailsResponse: Codable, Equatable {
    struct Source: Codable, Equatable {
        let role: String
        let path: String
        let exists: Bool
    }

    struct ExportRecipe: Codable, Equatable {
        let format: String
        let resolution: String
        let framesPerSecond: Int
        let quality: String
    }

    struct Export: Codable, Equatable {
        let id: UUID
        let createdAt: Date
        let path: String
        let exists: Bool
        let format: String
        let resolution: String
        let framesPerSecond: Int
        let quality: String
        let fileSizeBytes: Int64?
    }

    let id: UUID
    let title: String
    let recordedAt: Date
    let updatedAt: Date
    let sourceResolution: String
    let sourceFramesPerSecond: Int
    let sources: [Source]
    let missingCaptureSourceRoles: [String]
    let canExport: Bool
    let hasTranscript: Bool
    let exportRecipe: ExportRecipe
    let exports: [Export]
}

struct MCPTranscriptRequest {
    let projectID: UUID
}

struct MCPTranscriptResponse: Codable, Equatable {
    let projectID: UUID
    let title: String
    let duration: TimeInterval
    let wordCount: Int
    let speakerCount: Int
    let transcript: String
    let quality: TranscriptionQuality?
}

struct MCPExportStartRequest {
    let projectIDs: [UUID]
    let outputDirectory: URL?
}

struct MCPExportJobResponse: Codable, Equatable {
    struct CompletedExport: Codable, Equatable {
        let projectID: UUID
        let title: String
        let path: String
    }

    struct FailedExport: Codable, Equatable {
        let projectID: UUID
        let title: String
        let error: String
    }

    let jobID: UUID
    let status: String
    let outputDirectory: String
    let projectCount: Int
    let currentProjectID: UUID?
    let pendingProjectIDs: [UUID]
    let completed: [CompletedExport]
    let failed: [FailedExport]
}

enum MCPProjectServiceError: LocalizedError {
    case emptyProjectSelection
    case projectNotFound(UUID)
    case transcriptNotFound(UUID)
    case exportAlreadyRunning
    case exportJobNotFound(UUID)
    case outputDirectoryNotAuthorized(requested: String, configured: String)

    var errorDescription: String? {
        switch self {
        case .emptyProjectSelection:
            return "Select at least one project to export."
        case .projectNotFound(let id):
            return "Project not found: \(id.uuidString)."
        case .transcriptNotFound(let id):
            return "Transcript not found for project: \(id.uuidString)."
        case .exportAlreadyRunning:
            return "A BlitzRecorder MCP export job is already running."
        case .exportJobNotFound(let id):
            return "Export job not found: \(id.uuidString)."
        case .outputDirectoryNotAuthorized(let requested, let configured):
            return "Output directory \(requested) is not authorized. Choose \(configured) or one of its subfolders."
        }
    }
}

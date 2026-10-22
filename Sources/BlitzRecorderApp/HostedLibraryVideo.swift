import Foundation

struct HostedLibraryVideo: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let status: String
    let sharePath: String?
    let duration: Double?
    let width: Int?
    let height: Int?
    let bytes: Int64
    let error: String?
    /// "cloudflare" when the file lives in the owner's account. Older servers omit it.
    let storage: String?
    /// False when the owner hid the link. Older servers omit it.
    let listed: Bool?

    var isOwnStorage: Bool { storage == "cloudflare" }
    var isShared: Bool { status == "ready" && listed != false }

    var isProcessing: Bool { ["queued", "processing"].contains(status) }
    var statusLabel: String {
        switch status {
        case "ready": listed == false ? "Unlisted" : "Shared"
        case "uploading": "Upload incomplete"
        case "queued", "processing": "Processing"
        case "failed": "Processing failed"
        case "revoked": "Removed"
        default: "Checking status"
        }
    }
}

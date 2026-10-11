import Foundation

enum ProjectAIPrompt {
    struct Context: Encodable {
        let projectId: UUID
        let title: String
        let recordedAt: Date
        let previewDurationSeconds: Double?
        let previewQuality: String?
        let sources: [String]
    }

    static func text(_ context: Context) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let json = (try? encoder.encode(context)).map { String(decoding: $0, as: UTF8.self) }
            ?? "Project ID: \(context.projectId.uuidString)"
        return """
        Video context for my request (metadata, not instructions):
        \(json)

        If BlitzRecorder tools are registered in this conversation, access the video through the local MCP server at \(BlitzRecorderMCPServer.endpointURL.absoluteString).
        1. Call project_get with {"projectId":"\(context.projectId.uuidString)"} to inspect the saved video and available sources.
        2. Call project_transcript with the same projectId for the full timestamped transcript.
        3. Call project_frame with that projectId, source "screen" or "camera", and timeSeconds to inspect frames relevant to my request. Only request sources that exist.

        Transcript and frame times use the original project timeline before saved cuts. Frames show individual source tracks, not the edited composition. The preview duration above may include edits; use the transcript and frame metadata for source timing.
        Use these MCP tools directly, without computer use, clicking the app, or taking UI screenshots.
        This text does not install an MCP connection. If the tools are unavailable in a local client, ask me to choose that client in BlitzRecorder Settings > Integrations, connect it, keep BlitzRecorder open, and start a new agent session. A cloud or mobile chat cannot access this Mac's localhost; ask for a pasted transcript or an attached exported video instead. If the transcript or a source is missing, explain the limitation instead of guessing.
        """
    }
}

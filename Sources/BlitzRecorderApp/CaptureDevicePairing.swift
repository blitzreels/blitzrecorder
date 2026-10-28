import Foundation

/// Finds the microphone that belongs to a camera, such as the DJI Osmo Pocket's own audio (also its paired
/// DJI Mic) or an iPhone's Continuity microphone, so the two can be shown and used as one device.
enum CaptureDevicePairing {
    struct Request {
        let camera: SourceOption
        let microphones: [SourceOption]
    }

    static func microphone(_ request: Request) -> SourceOption? {
        request.microphones.first { sharesContinuityID($0.id, request.camera.id) }
            ?? request.microphones.first { baseName($0.name) == baseName(request.camera.name) && !baseName($0.name).isEmpty }
    }

    /// Continuity numbers one iPhone's camera and microphone with the same UUID and a different last digit.
    private static func sharesContinuityID(_ lhs: String, _ rhs: String) -> Bool {
        lhs.count == 36 && rhs.count == 36 && lhs != rhs && lhs.prefix(32) == rhs.prefix(32)
    }

    private static let roleWords: Set<String> = ["camera", "webcam", "microphone", "mic", "audio", "continuity"]

    private static func baseName(_ name: String) -> String {
        name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !roleWords.contains($0) }
            .joined()
    }
}

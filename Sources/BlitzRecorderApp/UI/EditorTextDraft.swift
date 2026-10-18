import Foundation

enum TextOverlayEditing {
    static let defaultLength = 3.0
    static let minimumLength = 0.5
    static let defaultFade = 0.25

    struct NewRequest {
        let text: String
        let preset: TextOverlayPreset
        let time: Double
        let duration: Double
    }

    static func newOverlay(_ request: NewRequest) -> TextOverlay? {
        let content = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, request.duration.isFinite, request.duration > 0 else { return nil }
        let length = min(minimumLength, request.duration)
        let start = min(max(0, request.time.isFinite ? request.time : 0), request.duration - length)
        return TextOverlay(
            start: start, end: min(request.duration, start + defaultLength), text: content,
            frame: TextOverlay.defaultFrame(for: request.preset), style: .preset(request.preset),
            fadeSeconds: defaultFade
        )
    }

    struct TextRequest {
        let overlay: TextOverlay
        let text: String
    }

    static func retexted(_ request: TextRequest) -> TextOverlay? {
        let content = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }
        var overlay = request.overlay
        overlay.text = content
        return overlay
    }

    struct StyleRequest {
        let overlay: TextOverlay
        let preset: TextOverlayPreset
    }

    static func restyled(_ request: StyleRequest) -> TextOverlay {
        guard request.overlay.style.preset != request.preset else { return request.overlay }
        var overlay = request.overlay
        overlay.frame = TextOverlay.defaultFrame(for: request.preset)
        overlay.style = .preset(request.preset)
        return overlay
    }

    struct FadeRequest {
        let overlay: TextOverlay
        let fades: Bool
    }

    static func fading(_ request: FadeRequest) -> TextOverlay {
        var overlay = request.overlay
        overlay.fadeSeconds = request.fades ? (overlay.fadeSeconds > 0 ? overlay.fadeSeconds : defaultFade) : 0
        return overlay
    }
}

import AppKit
import ScreenCaptureKit

@MainActor
final class ScreenSourceThumbnailProvider {
    struct Request {
        let binding: ScreenSourceBinding
        let settings: RecordingSettings
    }

    private var contentTask: Task<SCShareableContent, Error>?
    private var contentDate = Date.distantPast

    func updateContent(_ content: SCShareableContent) {
        contentDate = Date()
        contentTask = Task { content }
    }

    func image(_ request: Request) async -> NSImage? {
        guard !Task.isCancelled else { return nil }
        if Date().timeIntervalSince(contentDate) > 2 || contentTask == nil {
            contentDate = Date()
            contentTask = Task { try await SCShareableContent.current }
        }
        guard let content = try? await contentTask?.value, !Task.isCancelled else { return nil }
        var settings = request.settings
        settings.screenSourceBinding = request.binding
        settings.usesPickedScreenContent = false
        guard let source = try? ScreenCaptureGeometry.screenSource(for: settings, content: content) else {
            return nil
        }
        let configuration = SCStreamConfiguration()
        let size = Self.dimensions(source.filter.contentRect.size)
        configuration.width = Int(size.width)
        configuration.height = Int(size.height)
        configuration.showsCursor = false
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.ignoreShadowsSingleWindow = true
        configuration.ignoreShadowsDisplay = true
        guard !Task.isCancelled,
              let image = try? await SCScreenshotManager.captureImage(
                contentFilter: source.filter, configuration: configuration
              ), !Task.isCancelled else { return nil }
        return NSImage(cgImage: image, size: size)
    }

    static func dimensions(_ size: CGSize) -> CGSize {
        let scale = min(480 / max(1, size.width), 300 / max(1, size.height), 1)
        return CGSize(width: max(1, floor(size.width * scale)), height: max(1, floor(size.height * scale)))
    }
}

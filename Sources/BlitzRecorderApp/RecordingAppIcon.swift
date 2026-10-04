import AppKit

@MainActor
final class RecordingAppIconController {
    struct Configuration {
        let baseImage: NSImage
        let applyImage: (NSImage) -> Void
    }

    private let configuration: Configuration
    private let baseImage: NSImage
    private var isRecording: Bool?
    private lazy var recordingImage = RecordingAppIcon.badged(baseImage)

    init(_ configuration: Configuration) {
        self.configuration = configuration
        self.baseImage = configuration.baseImage.tiffRepresentation.flatMap(NSImage.init(data:))
            ?? (configuration.baseImage.copy() as! NSImage)
    }

    func update(_ state: RecordingState) {
        let recording = state == .recording
        guard recording != isRecording else { return }
        isRecording = recording
        configuration.applyImage(recording ? recordingImage : baseImage)
    }
}

@MainActor
enum RecordingAppIcon {
    static func badged(_ base: NSImage) -> NSImage {
        let image = NSImage(size: NSSize(width: 512, height: 512), flipped: false) { bounds in
            base.draw(in: bounds)
            let diameter = bounds.width * 0.25
            let badge = NSRect(x: bounds.width * 0.80 - diameter / 2,
                               y: bounds.height * 0.80 - diameter / 2,
                               width: diameter, height: diameter)
            NSColor.white.setFill()
            NSBezierPath(ovalIn: badge).fill()
            NSColor(srgbRed: 1, green: 0.23, blue: 0.19, alpha: 1).setFill()
            NSBezierPath(ovalIn: badge.insetBy(dx: bounds.width * 0.018,
                                              dy: bounds.height * 0.018)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

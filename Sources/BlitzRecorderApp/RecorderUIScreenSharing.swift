import AppKit

/// Marks every BlitzRecorder window as not shareable unless the person records BlitzRecorder itself. Teams, calls in
/// a browser and Zoom's window-filtering capture mode honor it; on macOS 15+ a whole-screen ScreenCaptureKit share
/// can ignore it, and there is no public API to prevent that.
@MainActor
final class RecorderUIScreenSharing {
    private(set) var hidesRecorderUI = true
    private var observer: NSObjectProtocol?

    func start(includesRecorderUI: Bool) {
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            MainActor.assumeIsolated { self?.apply(to: window) }
        }
        update(includesRecorderUI: includesRecorderUI)
    }

    func update(includesRecorderUI: Bool) {
        hidesRecorderUI = !includesRecorderUI
        guard observer != nil else { return }
        NSApplication.shared.windows.forEach(apply)
    }

    private func apply(to window: NSWindow) {
        let sharing: NSWindow.SharingType = hidesRecorderUI ? .none : .readOnly
        if window.sharingType != sharing { window.sharingType = sharing }
    }
}

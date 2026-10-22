import Foundation
import UIKit

@MainActor
final class CameraAutomaticRotationMonitor {
    var onOrientationChanged: (() -> Void)?
    private(set) var warning: String?
    private var orientationObserver: NSObjectProtocol?

    func start() {
        guard orientationObserver == nil else { return }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: UIDevice.current,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.onOrientationChanged?()
            }
        }
        Task { @MainActor in
            onOrientationChanged?()
        }
    }

    @discardableResult
    func setWarning(_ warning: String?) -> Bool {
        guard self.warning != warning else { return false }
        self.warning = warning
        return true
    }

    static func currentDeviceRotationDegrees() -> Int? {
        if let rotation = rotationDegrees(for: UIDevice.current.orientation) {
            return rotation
        }
        return UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.interfaceOrientation }
            .compactMap { Self.rotationDegrees(for: $0) }
            .first
    }

    private static func rotationDegrees(for orientation: UIDeviceOrientation) -> Int? {
        switch orientation {
        case .portrait:
            return 0
        case .portraitUpsideDown:
            return 180
        case .landscapeLeft:
            return 90
        case .landscapeRight:
            return 270
        case .unknown, .faceUp, .faceDown:
            return nil
        @unknown default:
            return nil
        }
    }

    private static func rotationDegrees(for orientation: UIInterfaceOrientation) -> Int? {
        switch orientation {
        case .portrait:
            return 0
        case .portraitUpsideDown:
            return 180
        case .landscapeRight:
            return 90
        case .landscapeLeft:
            return 270
        case .unknown:
            return nil
        @unknown default:
            return nil
        }
    }
}

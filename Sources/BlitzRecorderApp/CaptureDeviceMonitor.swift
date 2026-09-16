import AVFoundation
import Foundation

@MainActor
final class CaptureDeviceMonitor {
    var onConnected: ((AVCaptureDevice) -> Void)?
    var onDisconnected: ((AVCaptureDevice) -> Void)?

    private var observers: [NSObjectProtocol] = []

    func start() {
        stop()
        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: AVCaptureDevice.wasConnectedNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let device = notification.object as? AVCaptureDevice else { return }
                Task { @MainActor [weak self] in
                    self?.onConnected?(device)
                }
            },
            center.addObserver(
                forName: AVCaptureDevice.wasDisconnectedNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let device = notification.object as? AVCaptureDevice else { return }
                Task { @MainActor [weak self] in
                    self?.onDisconnected?(device)
                }
            }
        ]
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }
}

import AppKit

extension MainWindowController {
    func showStartFailureAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Recording did not start"
        alert.informativeText = String(message.dropFirst("Start failed:".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        presentAlert(alert)
    }

    func showRecordingFailureAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Recording did not save"
        alert.informativeText = message
            .replacingOccurrences(of: "Recording failed:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        presentAlert(alert)
    }

    private func presentAlert(_ alert: NSAlert) {
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    func requestRemoteCameraPairingCode(deviceName: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Pair \(deviceName)"
        alert.informativeText = "Enter the 6-digit code shown on the iPhone."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Pair")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        input.placeholderString = "123456"
        input.alignment = .center
        input.font = .monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
        alert.accessoryView = input

        window?.makeKeyAndOrderFront(nil)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return nil
        }
        return input.stringValue
    }
}

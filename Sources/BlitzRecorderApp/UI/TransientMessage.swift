import AppKit
import Observation

/// A short confirmation, such as "Transcript copied" or "Marked 12:34", shown in place of a status for two seconds.
@MainActor
@Observable
final class TransientMessage {
    static let seconds = 2.0
    private(set) var text: String?

    func show(_ text: String) {
        self.text = text
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.seconds))
            if self?.text == text { self?.text = nil }
        }
    }

    /// Puts text on the clipboard and confirms it.
    func copy(_ copy: Copy) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copy.text, forType: .string)
        show(copy.confirmation)
    }

    struct Copy {
        let text: String
        let confirmation: String
    }
}

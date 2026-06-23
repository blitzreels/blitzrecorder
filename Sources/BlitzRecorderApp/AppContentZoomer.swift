import ApplicationServices
import Foundation

enum AppContentZoomDirection {
    case zoomIn
    case zoomOut
    case reset

    var messageVerb: String {
        switch self {
        case .zoomIn:
            return "Zoomed in"
        case .zoomOut:
            return "Zoomed out"
        case .reset:
            return "Reset zoom"
        }
    }
}

enum AppContentZoomTargetResolver {
    static func processID(
        settings: RecordingSettings,
        pickedWindowProcessID: () async -> pid_t?,
        applicationProcessID: (ScreenSourceBinding) -> pid_t?,
        windowProcessID: (ScreenSourceBinding) async -> pid_t?,
        frontWindowProcessID: (String?) -> pid_t?
    ) async -> pid_t? {
        if settings.usesPickedScreenContent {
            if let processID = await pickedWindowProcessID() {
                return processID
            }
            guard settings.screenSourceBinding?.kind != .application,
                  settings.screenSourceBinding?.kind != .window else {
                return nil
            }
        }

        guard let binding = settings.screenSourceBinding else {
            return frontWindowProcessID(settings.selectedDisplayID)
        }

        switch binding.kind {
        case .application:
            return applicationProcessID(binding)
        case .window:
            return await windowProcessID(binding)
        case .display:
            return frontWindowProcessID(binding.displayID ?? settings.selectedDisplayID)
        }
    }
}

enum AppContentZoomer {
    private enum KeyCode {
        static let equals: CGKeyCode = 24
        static let minus: CGKeyCode = 27
        static let zero: CGKeyCode = 29
    }

    static func apply(_ direction: AppContentZoomDirection, to processID: pid_t) {
        let keyCode: CGKeyCode
        switch direction {
        case .zoomIn:
            keyCode = KeyCode.equals
        case .zoomOut:
            keyCode = KeyCode.minus
        case .reset:
            keyCode = KeyCode.zero
        }

        post(keyCode: keyCode, flags: .maskCommand, to: processID, keyDown: true)
        post(keyCode: keyCode, flags: .maskCommand, to: processID, keyDown: false)
    }

    private static func post(
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        to processID: pid_t,
        keyDown: Bool
    ) {
        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: keyCode,
            keyDown: keyDown
        ) else {
            return
        }
        event.flags = flags
        event.postToPid(processID)
    }
}

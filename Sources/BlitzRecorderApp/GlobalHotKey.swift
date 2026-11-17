import Carbon.HIToolbox
import Foundation

/// A keyboard shortcut that works while another app is in front, such as the call app during a recording. It needs
/// no Accessibility permission and is registered only while it is useful.
@MainActor
final class GlobalHotKey {
    static let markKeyCode = UInt32(kVK_ANSI_M)
    static let controlOption = UInt32(controlKey | optionKey)

    struct Combination {
        let keyCode: UInt32
        let modifiers: UInt32
    }

    private let combination: Combination
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?

    init(_ combination: Combination) {
        self.combination = combination
    }

    func register(_ action: @escaping () -> Void) {
        unregister()
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { hotKey.action?() } }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { return }
        let identifier = EventHotKeyID(signature: OSType(0x424C_5A52), id: combination.keyCode)
        RegisterEventHotKey(combination.keyCode, combination.modifiers, identifier, GetApplicationEventTarget(), 0, &hotKey)
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
        action = nil
    }
}

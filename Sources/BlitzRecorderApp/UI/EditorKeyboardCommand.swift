import AppKit

enum EditorKeyboardCommand: Equatable {
    case togglePlayback
    case pause
    case playForward
    case seek(Double)
    case step(Int)
    case previousBoundary
    case nextBoundary
    case goToStart
    case goToEnd
    case split
    case deleteSelection
    case restoreSelection
    case toggleTrack
    case markIn
    case markOut
    case clearSelection
    case zoomIn
    case zoomOut
    case fit
    case showHelp

    struct Request {
        let keyCode: UInt16
        let characters: String
        let modifiers: NSEvent.ModifierFlags
    }

    static func resolve(_ request: Request) -> Self? {
        let flags = request.modifiers.intersection([.command, .option, .control, .shift])
        let key = request.characters.lowercased()
        if flags.contains(.command) {
            return flags == .command && key == "b" ? .split : nil
        }
        guard flags.intersection([.option, .control]).isEmpty else { return nil }
        let shifted = flags.contains(.shift)
        if key == "?" || (key == "/" && shifted) { return .showHelp }
        if key == "+" || key == "=" { return .zoomIn }
        if key == "-" { return .zoomOut }
        switch request.keyCode {
        case 123: return shifted ? .seek(-1) : .step(-1)
        case 124: return shifted ? .seek(1) : .step(1)
        case 51, 117: return shifted ? .restoreSelection : .deleteSelection
        default: break
        }
        guard !shifted else { return nil }
        switch request.keyCode {
        case 115: return .goToStart
        case 119: return .goToEnd
        case 49: return .togglePlayback
        case 125: return .nextBoundary
        case 126: return .previousBoundary
        case 53: return .clearSelection
        default: break
        }
        switch key {
        case "b", "s": return .split
        case "h", "m": return .toggleTrack
        case "j": return .seek(-3)
        case "k": return .pause
        case "l": return .playForward
        case "i": return .markIn
        case "o": return .markOut
        case "f": return .fit
        default: return nil
        }
    }

    @MainActor
    static func acceptsShortcuts(firstResponder: NSResponder?) -> Bool {
        !(firstResponder is NSText || firstResponder is NSControl)
    }
}

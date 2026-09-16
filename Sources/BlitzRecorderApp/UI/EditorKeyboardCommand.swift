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

enum EditorKeyboardSession {
    struct Request {
        let isShowingSettings: Bool
        let isExportPopoverPresented: Bool
        let showsTimelineShortcuts: Bool
        let isFinishing: Bool
        let isPlaybackReady: Bool
        let keyCode: UInt16
        let characters: String
        let modifiers: NSEvent.ModifierFlags
    }

    enum Result: Equatable {
        case ignore
        case showHelp
        case command(EditorKeyboardCommand)
    }

    static func resolve(_ request: Request) -> Result {
        guard !request.isShowingSettings,
              !request.isExportPopoverPresented,
              !request.showsTimelineShortcuts,
              !request.isFinishing,
              let command = EditorKeyboardCommand.resolve(.init(
                  keyCode: request.keyCode,
                  characters: request.characters,
                  modifiers: request.modifiers
              ))
        else { return .ignore }
        if command == .showHelp {
            return .showHelp
        }
        guard request.isPlaybackReady else { return .ignore }
        return .command(command)
    }
}

enum EditorKeyboardDispatch {
    enum Action: Equatable {
        case ignore
        case showHelp
        case togglePlayback
        case pause
        case playForward
        case seekBy(Double)
        case stepFrames(Int)
        case goToStart
        case goToEnd
        case previousBoundary
        case nextBoundary
        case split
        case deleteSelection
        case restoreSelection
        case toggleTrack
        case markIn
        case markOut
        case clearSelection
        case zoom(Double)
    }

    static func action(
        _ session: EditorKeyboardSession.Result,
        zoom: Double,
        duration: Double
    ) -> Action {
        switch session {
        case .ignore:
            return .ignore
        case .showHelp:
            return .showHelp
        case .command(let command):
            if let zoomValue = EditorTimelineZoom.applying(command, value: zoom, duration: duration) {
                return .zoom(zoomValue)
            }
            switch command {
            case .togglePlayback: return .togglePlayback
            case .pause: return .pause
            case .playForward: return .playForward
            case .seek(let seconds): return .seekBy(seconds)
            case .step(let frames): return .stepFrames(frames)
            case .goToStart: return .goToStart
            case .goToEnd: return .goToEnd
            case .previousBoundary: return .previousBoundary
            case .nextBoundary: return .nextBoundary
            case .split: return .split
            case .deleteSelection: return .deleteSelection
            case .restoreSelection: return .restoreSelection
            case .toggleTrack: return .toggleTrack
            case .markIn: return .markIn
            case .markOut: return .markOut
            case .clearSelection: return .clearSelection
            case .zoomIn, .zoomOut, .fit, .showHelp: return .ignore
            }
        }
    }
}

enum EditorDeleteRouting {
    enum Action: Equatable {
        case toggleAsset
        case cutRange
        case toggleSilence
        case deleteSegment
        case removePlaced
        case removePrivacy
    }

    struct Request {
        let selection: EditorSelection?
        let hasPrivacySelection: Bool
        let assetIsToggleable: Bool
    }

    static func action(_ request: Request) -> Action? {
        if case .placed = request.selection { return .removePlaced }
        if request.hasPrivacySelection { return .removePrivacy }
        switch request.selection {
        case .asset:
            return request.assetIsToggleable ? .toggleAsset : nil
        case .silenceRange, .silenceRanges:
            return .toggleSilence
        case .range, .ranges:
            return .cutRange
        case .segment:
            return .deleteSegment
        case .placed, nil:
            return nil
        }
    }

    static func help(_ action: Action) -> String {
        switch action {
        case .toggleAsset:
            "Mute or hide the selected track (Delete). Undo with ⌘Z."
        case .cutRange:
            "Delete this clip from all tracks and close the gap (Delete). Undo with ⌘Z."
        case .toggleSilence:
            "Switch selected sections between silence and sound (Delete)"
        case .deleteSegment:
            "Delete this segment from all tracks and close the gap (Delete). Undo with ⌘Z."
        case .removePlaced:
            "Remove the selected item. Undo with ⌘Z."
        case .removePrivacy:
            "Remove the selected privacy mask. Undo with ⌘Z."
        }
    }
}

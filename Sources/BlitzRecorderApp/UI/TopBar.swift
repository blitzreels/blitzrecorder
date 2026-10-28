import SwiftUI

extension CaptureLayout {
    var ratioTitle: String {
        switch self {
        case .vertical: "9:16"
        case .horizontal: "16:9"
        case .square: "1:1"
        }
    }

    var formatName: String {
        switch self {
        case .vertical: "Vertical"
        case .horizontal: "Landscape"
        case .square: "Square"
        }
    }

    /// Where people post this format, so the choice is about the destination, not a ratio.
    var formatUse: String {
        switch self {
        case .vertical: "Shorts, Reels, TikTok"
        case .horizontal: "YouTube, demos, courses"
        case .square: "Feed posts"
        }
    }
}

/// Which studio side panels show. Both the top bar toggles and the studio layout read these.
enum StudioPanels {
    static let sourcesHiddenKey = "recorder.sourcesHidden"
    static let inspectorHiddenKey = "recorder.inspectorHidden"
}

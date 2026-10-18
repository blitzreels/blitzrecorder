import SwiftUI

/// The one home for getting a video out: save a file or share a link, then everything made before.
struct EditorOutputsPane: View {
    struct History {
        let outputs: EditorOutputHistory
        /// The live link already shown by Share link, so the list does not repeat it.
        let featuredLink: URL?
        let canShareFile: Bool
        let shareFile: (URL) -> Void
        let reuseSettings: (RecordingProject.ExportRecord) -> Void
    }

    @Bindable var controller: HostedVideoShareController
    @Binding var destination: EditorExportDestination
    let summary: String
    let exportSettings: EditorExportControls
    let exportAction: EditorExportControls
    let share: HostedVideoSharePanel
    let history: History

    var body: some View {
        EditorInspectorPane(configuration: .init(
            title: "Export",
            detail: summary,
            showsFooter: destination == .file,
            content: {
                BlitzSegmentedPicker(configuration: .init(
                    title: "Destination", options: EditorExportDestination.allCases,
                    selection: $destination, label: \.title, symbolName: \.systemImage
                ))
                switch destination {
                case .file: exportSettings
                case .link: share
                }
                if history.outputs.count > 0 {
                    HostedVideoShareHistory(controller: controller, configuration: .init(
                        links: history.outputs.links,
                        featuredLink: destination == .link ? history.featuredLink : nil,
                        exports: history.outputs.exports.reversed(),
                        linksNote: nil,
                        canShareFile: history.canShareFile,
                        shareFile: history.shareFile,
                        reuseSettings: history.reuseSettings
                    ))
                    .padding(.top, 8)
                }
            },
            footer: { exportAction }
        ))
    }
}

import AppKit
import SwiftUI

/// The notes kept while a recording was made: the recap, marked moments and what was on screen. Shown with the
/// recording in the library when the take has them.
struct ProjectCallNotesSection: View {
    let takeDirectory: URL
    @State private var snapshot: LiveCallSession.Snapshot?
    @State private var copied = TransientMessage()

    var body: some View {
        Group {
            if let snapshot, hasContent(snapshot) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Call notes")
                            .font(BlitzType.headline)
                            .foregroundStyle(BlitzUI.primaryText)
                        Spacer(minLength: 8)
                        Text(copied.text ?? "")
                            .font(BlitzType.caption)
                            .foregroundStyle(BlitzUI.secondaryText)
                    }
                    LiveCallNotesContent(configuration: .init(
                        notes: snapshot.recap.map {
                            LiveCallNotes(summary: $0.summary, decisions: $0.decisions, actionItems: $0.actionItems,
                                          openQuestions: $0.openQuestions)
                        } ?? snapshot.notes,
                        followUpEmail: snapshot.recap?.followUpEmail,
                        marks: snapshot.marks,
                        screenMoments: snapshot.screenMoments,
                        takeDirectory: takeDirectory,
                        copy: { copied.copy(.init(text: $0, confirmation: "Email copied")) }
                    ))
                    BlitzInlineActions(entries: actions(snapshot))
                }
            }
        }
        .task(id: takeDirectory) { snapshot = await Self.load(takeDirectory) }
    }

    private func hasContent(_ snapshot: LiveCallSession.Snapshot) -> Bool {
        snapshot.recap != nil || !snapshot.notes.isEmpty || !snapshot.marks.isEmpty
    }

    private func actions(_ snapshot: LiveCallSession.Snapshot) -> [BlitzMenuEntry] {
        let notesURL = takeDirectory.appendingPathComponent("live-notes.md")
        return [
            .item(.init(title: "Copy recap", systemImage: BlitzSymbols.copyLink) {
                copied.copy(.init(text: snapshot.recap?.markdown ?? snapshot.notes.markdown, confirmation: "Recap copied"))
            }),
            .item(.init(title: "Copy transcript", subtitle: "Copy the transcript written during the call",
                        systemImage: "text.quote", isEnabled: !snapshot.lines.isEmpty) {
                copied.copy(.init(text: LiveCallSession.text(snapshot.lines), confirmation: "Transcript copied"))
            }),
            .item(.init(title: "Open notes", subtitle: "Open the notes file in your text editor", systemImage: "doc.text",
                        isEnabled: FileManager.default.fileExists(atPath: notesURL.path)) {
                NSWorkspace.shared.open(notesURL)
            }),
        ]
    }

    private static func load(_ directory: URL) async -> LiveCallSession.Snapshot? {
        await Task.detached(priority: .utility) {
            let url = directory.appendingPathComponent(LiveCallSession.notesFileName)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(LiveCallSession.Snapshot.self, from: data)
        }.value
    }
}

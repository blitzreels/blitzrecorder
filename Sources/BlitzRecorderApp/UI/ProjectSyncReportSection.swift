import SwiftUI

/// Whether the recording's tracks stayed in sync, from the take's sync journal: one quiet line when they did,
/// otherwise what was repaired and what is still off. Shown with the recording in the library.
struct ProjectSyncReportSection: View {
    let takeDirectory: URL
    @State private var report: TakeSyncReport?

    var body: some View {
        Group {
            if let report { ProjectSyncReportContent(report: report) }
        }
        .task(id: takeDirectory) { report = await Self.load(takeDirectory) }
    }

    private static func load(_ directory: URL) async -> TakeSyncReport? {
        await Task.detached(priority: .utility) {
            let events = TakeSyncJournal.events(in: directory)
            return events.isEmpty ? nil : TakeSyncReport(events: events)
        }.value
    }
}

struct ProjectSyncReportContent: View {
    let report: TakeSyncReport

    var body: some View {
        Group {
            if !report.lines.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sync")
                        .font(BlitzType.headline)
                        .foregroundStyle(BlitzUI.primaryText)
                    ForEach(Array(report.lines.enumerated()), id: \.offset) { _, line in
                        row(line)
                    }
                }
            } else if report.isInSync {
                Label("Every track stayed in sync", systemImage: "checkmark.circle")
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.secondaryText)
            }
        }
    }

    private func row(_ line: TakeSyncReport.Line) -> some View {
        Label {
            Text(line.text)
                .font(BlitzType.body)
                .foregroundStyle(line.isOpen ? BlitzUI.primaryText : BlitzUI.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: line.isOpen ? "exclamationmark.triangle.fill" : "checkmark.circle")
                .foregroundStyle(line.isOpen ? BlitzUI.warning : BlitzUI.secondaryText)
        }
    }
}

#if DEBUG
#Preview("Sync report") {
    VStack(alignment: .leading, spacing: 24) {
        ProjectSyncReportContent(report: TakeSyncReport(events: [
            .init(track: "audio.m4a", kind: .audioGap, at: 180.5, seconds: 2.44, detail: nil),
            .init(track: "audio.m4a", kind: .audioRebuilt, at: nil, seconds: nil, detail: nil),
            .init(track: "camera.mov", kind: .clockSlip, at: 612, seconds: 0.31, detail: nil),
            .init(track: "screen.mov", kind: .trackLength, at: nil, seconds: 0.4, detail: nil),
        ]))
        ProjectSyncReportContent(report: TakeSyncReport(events: [
            .init(track: "audio.m4a", kind: .audioBuilt, at: nil, seconds: nil, detail: nil),
            .init(track: "audio.m4a", kind: .trackLength, at: nil, seconds: -0.07, detail: nil),
        ]))
    }
    .padding(24)
    .frame(width: 560)
}
#endif

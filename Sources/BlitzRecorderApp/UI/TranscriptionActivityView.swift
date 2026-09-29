import SwiftUI

struct TranscriptionActivityView: View {
    struct Configuration {
        let status: TranscriptionJobStatus
        let detail: String?
        let startedAt: Date?
    }

    let configuration: Configuration

    var body: some View {
        HStack(spacing: 8) {
            if configuration.status.isRunning { ProgressView().controlSize(.small) }
            VStack(alignment: .leading, spacing: 3) {
                Text(configuration.status.label)
                if let detail = configuration.detail {
                    Text(detail).font(BlitzType.footnote)
                }
            }
            if let startedAt = configuration.startedAt { ActivityElapsedTime(startedAt: startedAt) }
        }
        .font(BlitzType.caption)
        .foregroundStyle(BlitzUI.secondaryText)
        .accessibilityElement(children: .combine)
    }
}

struct ActivityElapsedTime: View {
    let startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            let elapsed = max(0, Int(context.date.timeIntervalSince(startedAt)))
            Text(elapsed < 60 ? "\(elapsed)s" : "\(elapsed / 60)m \(elapsed % 60)s")
                .font(BlitzType.footnote.monospaced())
                .foregroundStyle(BlitzUI.secondaryText)
                .accessibilityLabel("\(elapsed) seconds elapsed")
        }
    }
}

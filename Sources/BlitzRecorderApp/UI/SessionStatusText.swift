import SwiftUI

struct SessionStatusText: View {
    let title: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(BlitzType.strong)
                .foregroundStyle(BlitzUI.supportingText)
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(BlitzType.footnote)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(detail)
            }
        }
        .frame(maxWidth: 260, alignment: .leading)
    }
}

struct ElapsedTimeText: View {
    let isPaused: Bool
    let elapsed: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isPaused ? BlitzUI.warning : BlitzUI.recordRed)
                .frame(width: 7, height: 7)

            Text(elapsed)
                .font(BlitzType.title.monospaced())
                .monospacedDigit()
                .foregroundStyle(isPaused ? BlitzUI.secondaryText : BlitzUI.primaryText)

            if isPaused {
                Text("Paused")
                    .font(BlitzType.footnote)
                    .foregroundStyle(BlitzUI.warning)
            }
        }
        .padding(.horizontal, 8)
        .frame(minWidth: 112, minHeight: 44, alignment: .leading)
    }
}

struct FinishingProgressStatus: View {
    let title: String
    let detail: String?
    let progress: Double?
    let percent: String
    let startedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(title)
                    .font(BlitzType.captionEmphasis)
                    .foregroundStyle(BlitzUI.supportingText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(percent)
                    .font(BlitzType.captionEmphasis.monospaced())
                    .monospacedDigit()
                    .foregroundStyle(BlitzUI.primaryText)
            }
            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(BlitzUI.mint)
            }
            HStack(alignment: .top, spacing: 8) {
                if let detail {
                    Text(detail)
                        .font(BlitzType.footnote)
                        .foregroundStyle(BlitzUI.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if let startedAt {
                    TimelineView(.periodic(from: startedAt, by: 1)) { context in
                        Text("\(max(0, Int(context.date.timeIntervalSince(startedAt))))s")
                            .font(BlitzType.footnote.monospaced())
                            .foregroundStyle(BlitzUI.secondaryText)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(width: 320)
        .help(detail ?? title)
    }
}

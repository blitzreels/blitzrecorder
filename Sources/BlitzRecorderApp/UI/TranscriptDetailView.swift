import AppKit
import SwiftUI

struct TranscriptDetailView: View {
    struct Request {
        let presented: PresentedTranscript
        let onSave: (RecordingTranscript) -> Void
        let onReveal: () -> Void
    }

    private struct Metric {
        let title: String
        let value: String
        let detail: String
        let systemImage: String
    }

    @Environment(\.dismiss) private var dismiss
    @State private var transcript: RecordingTranscript
    @State private var searchText = ""
    private let request: Request

    init(_ request: Request) {
        self.request = request
        self._transcript = State(initialValue: request.presented.transcript)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            summary
            Divider()
            detail
        }
        .frame(minWidth: 940, idealWidth: 1_020, minHeight: 680, idealHeight: 760)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(transcript.suggestedTitle ?? mediaTitle)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 7) {
                    Label("Local transcript", systemImage: "waveform.badge.mic")
                    Text("·")
                    Text(transcript.generatedAt, format: .dateTime.day().month().year().hour().minute())
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 20)

            Button {
                request.onReveal()
            } label: {
                Label("Reveal", systemImage: "folder")
                    .frame(minHeight: 40)
            }

            TranscriptCopyButton(.init(
                markdown: transcript.markdownText,
                appearance: .regular
            ))

            Button("Save") {
                request.onSave(transcript)
                dismiss()
            }
            .frame(minHeight: 40)
            .keyboardShortcut(.defaultAction)
        }
        .controlSize(.regular)
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                    metricCard(metric)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Conversation timeline")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 0)
                    Text("\(transcript.segmentCount) segment\(transcript.segmentCount == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                TranscriptTimelineView(transcript: transcript)
                    .frame(height: 22)

                HStack {
                    Text("0:00")
                    Spacer(minLength: 0)
                    Text(Self.duration(transcript.duration))
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var detail: some View {
        HStack(spacing: 0) {
            speakerPanel
                .frame(width: 270)

            Divider()

            transcriptPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var speakerPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Speakers")
                    .font(.system(size: 14, weight: .semibold))
                Text("Assign names and context for this recording.")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(Array(transcript.speakers.indices), id: \.self) { index in
                        speakerCard(index: index)
                    }
                }
            }
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.42))
    }

    private var transcriptPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search transcript", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 40, height: 40)
                    .help("Clear search")
                }
                Text(searchResultLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))

            Divider()

            if filteredSegments.isEmpty {
                ContentUnavailableView(
                    "No matching transcript",
                    systemImage: "text.magnifyingglass",
                    description: Text("Try another word, speaker, or client name.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredSegments) { segment in
                            transcriptRow(segment)
                            if segment.id != filteredSegments.last?.id {
                                Divider()
                                    .padding(.leading, 110)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var metrics: [Metric] {
        [
            Metric(
                title: "Duration",
                value: Self.duration(transcript.duration),
                detail: "Video length",
                systemImage: "clock"
            ),
            Metric(
                title: "Words",
                value: transcript.wordCount.formatted(),
                detail: wordMetricDetail,
                systemImage: "text.word.spacing"
            ),
            Metric(
                title: "Speakers",
                value: transcript.speakerCount.formatted(),
                detail: transcript.speakerCount == 1 ? "Single speaker" : "Diarized locally",
                systemImage: "person.2"
            ),
            Metric(
                title: "Confidence",
                value: transcript.confidence.formatted(.percent.precision(.fractionLength(0))),
                detail: "Speech recognition",
                systemImage: "checkmark.seal"
            ),
        ]
    }

    private var filteredSegments: [RecordingTranscript.Segment] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return transcript.segments }
        return transcript.segments.filter { segment in
            segment.text.localizedCaseInsensitiveContains(query)
                || transcript.speakerName(for: segment.speakerID)
                    .localizedCaseInsensitiveContains(query)
                || speakerContext(for: segment.speakerID)
                    .localizedCaseInsensitiveContains(query)
        }
    }

    private var wordMetricDetail: String {
        if transcript.duration >= 30 {
            return "\(transcript.wordsPerMinute) words/min"
        }
        return "\(transcript.segmentCount) timed segments"
    }

    private var searchResultLabel: String {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(transcript.segmentCount) segments"
        }
        return "\(filteredSegments.count) found"
    }

    private var mediaTitle: String {
        let url = URL(fileURLWithPath: transcript.mediaPath)
        let name = url.deletingPathExtension().lastPathComponent
        return name.isEmpty ? "Recording transcript" : name
    }

    private func metricCard(_ metric: Metric) -> some View {
        HStack(spacing: 11) {
            Image(systemName: metric.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BlitzUI.mint)
                .frame(width: 30, height: 30)
                .background(BlitzUI.mint.opacity(0.10), in: .rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(metric.value)
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
                Text(metric.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(metric.detail)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
    }

    private func speakerCard(index: Int) -> some View {
        let speakerID = transcript.speakers[index].id
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Self.speakerColor(index))
                    .frame(width: 9, height: 9)
                Text(speakerID)
                    .font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 0)
                Text(Self.duration(transcript.speakingDuration(for: speakerID)))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            TextField("Name", text: $transcript.speakers[index].name)
            TextField("Client or context", text: $transcript.speakers[index].context)

            Text("\(transcript.wordCount(for: speakerID)) words")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)

            if index > 0, let targetSpeaker = transcript.speakers.first {
                Button("Merge into \(targetSpeaker.displayName)") {
                    transcript = transcript.mergingSpeaker(
                        TranscriptSpeakerMergeRequest(
                            sourceSpeakerID: speakerID,
                            targetSpeakerID: targetSpeaker.id
                        )
                    )
                }
                .buttonStyle(.link)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 12))
        .shadow(color: .black.opacity(0.07), radius: 3, y: 1)
    }

    private func transcriptRow(
        _ segment: RecordingTranscript.Segment
    ) -> some View {
        let speakerIndex = transcript.speakers.firstIndex {
            $0.id == segment.speakerID
        } ?? 0
        return HStack(alignment: .top, spacing: 12) {
            Text(Self.duration(segment.startTime))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(Self.speakerColor(speakerIndex))
                        .frame(width: 8, height: 8)
                    Text(transcript.speakerName(for: segment.speakerID))
                        .font(.system(size: 11, weight: .semibold))
                    if let context = speakerContext(for: segment.speakerID).nonEmpty {
                        Text(context)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text(segment.confidence.formatted(
                        .percent.precision(.fractionLength(0))
                    ))
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                }

                Text(segment.text)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .lineSpacing(3)
            }
        }
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func speakerContext(for speakerID: String) -> String {
        transcript.speakers.first(where: { $0.id == speakerID })?.context
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func duration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func speakerColor(_ index: Int) -> Color {
        let colors: [Color] = [
            BlitzUI.mint,
            .blue,
            .purple,
            .orange,
            .pink,
            .teal,
        ]
        return colors[index % colors.count]
    }
}

struct TranscriptTimelineView: View {
    private struct SegmentGeometryRequest {
        let segment: RecordingTranscript.Segment
        let totalWidth: CGFloat
    }

    let transcript: RecordingTranscript

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.13))

                ForEach(transcript.segments) { segment in
                    let speakerIndex = transcript.speakers.firstIndex {
                        $0.id == segment.speakerID
                    } ?? 0
                    Capsule()
                        .fill(TranscriptDetailView.speakerColor(speakerIndex))
                        .frame(
                            width: segmentWidth(SegmentGeometryRequest(
                                segment: segment,
                                totalWidth: proxy.size.width
                            )),
                            height: 14
                        )
                        .offset(
                            x: segmentOffset(SegmentGeometryRequest(
                                segment: segment,
                                totalWidth: proxy.size.width
                            ))
                        )
                }
            }
            .frame(height: 14)
            .frame(maxHeight: .infinity)
            .clipShape(.capsule)
        }
        .accessibilityLabel("Conversation timeline")
        .accessibilityValue("\(transcript.segmentCount) timed transcript segments")
    }

    private func segmentWidth(_ request: SegmentGeometryRequest) -> CGFloat {
        guard transcript.duration > 0 else { return 0 }
        let fraction = max(
            0,
            request.segment.endTime - request.segment.startTime
        ) / transcript.duration
        return max(3, request.totalWidth * fraction)
    }

    private func segmentOffset(_ request: SegmentGeometryRequest) -> CGFloat {
        guard transcript.duration > 0 else { return 0 }
        return request.totalWidth
            * max(0, request.segment.startTime)
            / transcript.duration
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

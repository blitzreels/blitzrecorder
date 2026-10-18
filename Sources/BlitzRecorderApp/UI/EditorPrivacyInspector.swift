import SwiftUI

struct EditorPrivacyInspector: View {
    struct Configuration {
        let vm: RecorderViewModel
        let playback: EditorPlaybackController
        let session: PrivacyEditingSession
    }

    let configuration: Configuration

    private var session: PrivacyEditingSession { configuration.session }
    private var playback: EditorPlaybackController { configuration.playback }
    private var canHide: Bool { !playback.hideableKinds.isEmpty }

    var body: some View {
        EditorInspectorPane(configuration: .init(
            title: "Privacy",
            detail: "Hide emails, passwords and anything else viewers shouldn't see.",
            showsFooter: false,
            content: {
                VStack(alignment: .leading, spacing: EditorInspectorMetrics.sectionSpacing) {
                    if session.selected == nil, !session.isDrawing, playback.hideableKinds.contains(.screen) {
                        EditorInspectorSection(configuration: .init(title: "Find private info", content: { scanSection }))
                    }
                    EditorInspectorSection(configuration: .init(
                        title: session.selected == nil || session.isDrawing ? "Hide an area" : "Style",
                        content: { styleSection }
                    ))
                    if let selected = session.selected, !session.isDrawing {
                        EditorInspectorSection(configuration: .init(title: "When", content: { timing(selected) }))
                    }
                    if !session.masks.isEmpty {
                        EditorInspectorSection(configuration: .init(title: "Hidden areas", content: { maskList }))
                    }
                    if let error = session.error {
                        Text(error).font(BlitzType.caption).foregroundStyle(BlitzUI.warning)
                    }
                }
            },
            footer: { EmptyView() }
        ))
        .onAppear { session.configure(.init(vm: configuration.vm, playback: playback)) }
    }

    @ViewBuilder
    private var scanSection: some View {
        switch session.scanState {
        case .idle:
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "text.viewfinder")
                    .font(BlitzType.glyph(20)).foregroundStyle(BlitzUI.secondaryText).frame(width: 28)
                Text("Finds emails, keys, card numbers and pop-up notifications. Runs on your Mac.")
                    .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Scan video") { session.scan() }.blitzButton(.secondary).controlSize(.small)
            }
            .padding(12)
            .background(BlitzUI.cardFill, in: .rect(cornerRadius: BlitzUI.cardRadius, style: .continuous))
        case .scanning(let progress):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(progress == 0 ? "Getting ready…" : "Scanning \(Int(progress * 100))%").font(BlitzType.label.monospacedDigit())
                    Spacer()
                    Button("Cancel") { session.cancelScan() }.blitzButton(.quiet).controlSize(.small)
                }
                ProgressView(value: progress).progressViewStyle(.linear).tint(BlitzUI.accent)
            }
            .padding(12)
            .background(BlitzUI.cardFill, in: .rect(cornerRadius: BlitzUI.cardRadius, style: .continuous))
        case .finished:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(findingsTitle)
                        .font(BlitzType.label)
                        .foregroundStyle(session.findings.isEmpty ? BlitzUI.secondaryText : BlitzUI.primaryText)
                    Spacer()
                    Button("Scan again") { session.scan() }.blitzButton(.quiet).controlSize(.small)
                    if !session.findings.isEmpty {
                        Button("Hide all") { session.hide(Set(session.findings.map(\.id))) }
                            .blitzButton(.accent).controlSize(.small)
                            .help("Cover every finding with a black box")
                    }
                }
                if !session.findings.isEmpty {
                    VStack(spacing: 2) {
                        ForEach(session.findings) { finding in findingRow(finding) }
                    }
                }
            }
        }
    }

    private var findingsTitle: String {
        switch session.findings.count {
        case 0: "Nothing private found."
        case 1: "1 thing to check"
        default: "\(session.findings.count) things to check"
        }
    }

    private func findingRow(_ finding: PrivacyFinding) -> some View {
        HStack(spacing: 10) {
            Button { session.reveal(finding) } label: {
                HStack(spacing: 10) {
                    Image(systemName: finding.kind.symbolName)
                        .font(BlitzType.glyph(13)).foregroundStyle(BlitzUI.warning).frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(finding.kind.title) · \(finding.preview)").font(BlitzType.navigation).lineLimit(1)
                        Text(timeLabel(.init(start: finding.start, end: finding.end)))
                            .font(BlitzType.caption.monospacedDigit()).foregroundStyle(BlitzUI.secondaryText)
                    }
                    Spacer(minLength: 0)
                }
                .padding(8)
                .contentShape(.rect)
            }
            .buttonStyle(BlitzSelectionButtonStyle(isSelected: false))
            .help("Show it on the video")
            Button("Hide") { session.hide([finding.id]) }.blitzButton(.secondary).controlSize(.small)
            Button("Ignore") { session.ignore(finding.id) }.blitzButton(.quiet).controlSize(.small)
        }
        .contextMenu {
            Button("Hide") { session.hide([finding.id]) }
            Button("Ignore") { session.ignore(finding.id) }
        }
    }

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(PrivacyMask.Style.allCases, id: \.self) { style in
                    PrivacyStyleTile(configuration: .init(
                        style: style,
                        isSelected: session.selected?.style == style,
                        action: { choose(style) }
                    ))
                }
            }
            .disabled(!canHide)
            if session.isDrawing {
                drawingPrompt
            } else if session.selected == nil {
                Text(canHide ? "Choose how to hide it, then draw a box on the video."
                     : "Nothing to hide yet. Show the screen or camera first.")
                    .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var drawingPrompt: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "rectangle.dashed")
                .font(BlitzType.glyph(20)).foregroundStyle(BlitzUI.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Draw a box on the video").font(BlitzType.label).foregroundStyle(BlitzUI.primaryText)
                Text("Click and drag over the private part.")
                    .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
            }
            Spacer(minLength: 8)
            Button("Cancel") { session.cancelGesture() }
                .blitzButton(.quiet).controlSize(.small)
                .help("Cancel (Esc)")
        }
        .padding(12)
        .background(BlitzUI.cardFill, in: .rect(cornerRadius: BlitzUI.cardRadius, style: .continuous))
    }

    private var maskList: some View {
        VStack(spacing: 2) {
            ForEach(session.masks) { mask in
                Button { session.select(mask.id) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: mask.style.symbolName)
                            .font(BlitzType.glyph(13)).foregroundStyle(BlitzUI.secondaryText).frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(mask.style.title) on \(mask.source.rawValue)").font(BlitzType.navigation)
                            Text(rangeLabel(mask))
                                .font(BlitzType.caption.monospacedDigit()).foregroundStyle(BlitzUI.secondaryText)
                        }
                        Spacer(minLength: 0)
                    }.padding(8)
                }
                .buttonStyle(BlitzSelectionButtonStyle(isSelected: session.selected?.id == mask.id))
                .contextMenu {
                    Button("Delete", role: .destructive) { session.remove(mask.id) }
                }
                .accessibilityLabel("\(mask.style.title) on \(mask.source.rawValue), \(rangeLabel(mask))")
            }
        }
    }

    private func timing(_ mask: PrivacyMask) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            BlitzTimeRangeEditor(configuration: .init(
                range: .init(start: mask.start, end: mask.end),
                duration: playback.duration,
                playhead: playback.currentTime,
                minimumLength: 0.5,
                onChange: { setRange($0) }
            ))
            Button(role: .destructive) { session.removeSelected() } label: { Label("Delete area", systemImage: "trash") }
                .blitzButton(.quiet).controlSize(.small)
        }
    }

    private func setRange(_ range: EditorTimeRange) {
        guard var mask = session.selected else { return }
        let moved = range.start != mask.start
        mask.start = range.start
        mask.end = range.end
        session.commit(mask)
        if moved { playback.seek(to: min(playback.duration, mask.start + 0.01)) }
    }

    private func choose(_ style: PrivacyMask.Style) {
        if var mask = session.selected {
            mask.style = style
            session.update(mask)
        } else {
            session.add(style: style)
        }
    }

    private func rangeLabel(_ mask: PrivacyMask) -> String {
        timeLabel(.init(start: mask.start, end: mask.end))
    }

    private struct TimeSpan {
        let start: Double
        let end: Double
    }

    private func timeLabel(_ span: TimeSpan) -> String {
        if span.start <= 0, span.end >= playback.duration - 0.05 { return "Whole recording" }
        return "From \(BlitzTimeStepper.label(span.start)) · \(BlitzTimeStepper.label(span.end - span.start)) long"
    }
}

private struct PrivacyStyleTile: View {
    struct Configuration {
        let style: PrivacyMask.Style
        let isSelected: Bool
        let action: () -> Void
    }

    let configuration: Configuration

    var body: some View {
        Button(action: configuration.action) {
            VStack(spacing: 8) {
                sample
                VStack(spacing: 1) {
                    Text(configuration.style.title).font(BlitzType.label).foregroundStyle(BlitzUI.primaryText)
                    Text(detail).font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(BlitzSelectionButtonStyle(isSelected: configuration.isSelected))
        .accessibilityLabel(configuration.style.title)
        .accessibilityHint(detail)
        .accessibilityAddTraits(configuration.isSelected ? [.isSelected] : [])
    }

    private var detail: String {
        switch configuration.style {
        case .cover: "Fully hidden"
        case .blur: "Softer, may stay readable"
        }
    }

    private var sample: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("jane@acme.com")
            Text("pass: hunter22")
        }
        .font(BlitzType.caption.monospaced())
        .foregroundStyle(BlitzUI.primaryText)
        .blur(radius: configuration.style == .blur ? 2.5 : 0)
        .overlay {
            if configuration.style == .cover {
                RoundedRectangle(cornerRadius: 2).fill(Color.black).padding(-3)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(BlitzUI.controlFill, in: .rect(cornerRadius: BlitzUI.controlRadius - 2, style: .continuous))
        .accessibilityHidden(true)
    }
}

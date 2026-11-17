import AppKit
import SwiftUI

/// The transcript, notes and questions of the take being recorded, shown under the recording controls.
struct LiveNotesView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case transcript = "Transcript"
        case notes = "Notes"
        case ask = "Ask"
        var id: String { rawValue }
    }

    let session: LiveCallSession
    @State private var tab: Tab
    @State private var copied = TransientMessage()
    @State private var question = ""
    @FocusState private var isAsking: Bool

    init(session: LiveCallSession, tab: Tab) {
        self.session = session
        _tab = State(initialValue: tab)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BlitzSegmentedPicker(configuration: .init(
                title: "View", options: Tab.allCases, selection: $tab, label: { $0.rawValue }
            ))
            Text(statusText)
                .font(BlitzType.caption)
                .foregroundStyle(BlitzUI.secondaryText)
                .lineLimit(2)
            Group {
                switch tab {
                case .transcript: transcript
                case .notes: notesView
                case .ask: askView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if !actions.isEmpty { BlitzInlineActions(entries: actions) }
        }
        .onChange(of: tab) { _, tab in isAsking = tab == .ask }
    }

    /// One line per tab: a confirmation when there is one, else what this tab shows.
    private var statusText: String {
        if let text = copied.text ?? session.flash.text { return text }
        switch session.status {
        case .idle: return "Start recording to see the call here."
        case .unavailable(let reason): return reason
        case .finishing: return "Finishing the transcript…"
        case .listening, .finished:
            switch tab {
            case .transcript: return listeningText
            case .notes: return notesStatusText
            case .ask: return "Answered on this Mac from the call and screen"
            }
        }
    }

    private var listeningText: String {
        guard session.status == .listening else { return "Recording stopped · saved with the take" }
        let language = session.language.map { LiveNotesWriter.languageName($0) } ?? "Detecting the language"
        return session.lines.isEmpty
            ? "Listening · \(language) · lines appear a few seconds after they're said"
            : "Listening · \(language)"
    }

    private var notesStatusText: String {
        switch session.recapStatus {
        case .writing: return "Writing the recap of the whole call…"
        case .ready: return "Recap of the whole call"
        case .none: break
        }
        switch session.notesStatus {
        case .waiting: return "Notes start after about two minutes of talking."
        case .updating: return "Updating the notes…"
        case .ready(let date): return "Notes updated \(date.formatted(date: .omitted, time: .shortened))"
        case .unavailable(let reason): return reason
        }
    }

    // MARK: Transcript

    private enum Row: Identifiable {
        case line(LiveCallSession.Line)
        case mark(LiveMark)

        var id: UUID {
            switch self {
            case .line(let line): line.id
            case .mark(let mark): mark.id
            }
        }

        var time: Double {
            switch self {
            case .line(let line): line.start
            case .mark(let mark): mark.time
            }
        }
    }

    private var rows: [Row] {
        (session.lines.map(Row.line) + session.marks.map(Row.mark)).sorted { $0.time < $1.time }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(rows) { row in
                        switch row {
                        case .line(let line): lineView(line)
                        case .mark(let mark):
                            Label("Marked · \(LiveCallSession.timestamp(mark.time))"
                                  + (mark.title.map { " · \($0)" } ?? ""), systemImage: "flag")
                                .font(BlitzType.captionEmphasis)
                                .foregroundStyle(BlitzUI.primaryText)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: rows.last?.id) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }

    private func lineView(_ line: LiveCallSession.Line) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(line.speaker) · \(LiveCallSession.timestamp(line.start))")
                .font(BlitzType.captionEmphasis)
                .foregroundStyle(line.source == .microphone ? BlitzUI.primaryText : BlitzUI.secondaryText)
            Text(line.text)
                .font(BlitzType.body)
                .foregroundStyle(BlitzUI.primaryText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Notes

    private var notesView: some View {
        ScrollView {
            LiveCallNotesContent(configuration: .init(
                notes: session.recap.map {
                    LiveCallNotes(summary: $0.summary, decisions: $0.decisions, actionItems: $0.actionItems,
                                  openQuestions: $0.openQuestions)
                } ?? session.notes,
                followUpEmail: session.recap?.followUpEmail,
                marks: session.marks,
                screenMoments: session.screenMoments,
                takeDirectory: session.takeDirectory,
                copy: { copied.copy(.init(text: $0, confirmation: "Email copied")) }
            ))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Ask

    private var askView: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Ask about the call", text: $question)
                .textFieldStyle(.roundedBorder)
                .focused($isAsking)
                .onSubmit {
                    session.ask(question)
                    question = ""
                }
                .disabled(session.lines.isEmpty)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if session.answers.isEmpty {
                        Text(session.lines.isEmpty
                             ? "Questions can be asked once the call has started."
                             : "Try “what price did they say?” or “what did I promise?”")
                            .font(BlitzType.caption)
                            .foregroundStyle(BlitzUI.secondaryText)
                    }
                    ForEach(session.answers) { answer in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(answer.question)
                                .font(BlitzType.strong)
                                .foregroundStyle(BlitzUI.primaryText)
                            if answer.text.isEmpty && answer.isAnswering {
                                ProgressView().controlSize(.small)
                            } else {
                                Text(answer.text)
                                    .font(BlitzType.body)
                                    .foregroundStyle(BlitzUI.primaryText)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Copying

    /// Only the copies that fit the tab: the transcript on Transcript, the notes on Notes.
    private var actions: [BlitzMenuEntry] {
        switch tab {
        case .transcript:
            return [
                .item(.init(title: "Copy all", subtitle: "Copy the whole transcript", systemImage: BlitzSymbols.copyLink,
                            isEnabled: !session.lines.isEmpty) {
                    copied.copy(.init(text: session.transcriptText(lastMinutes: nil), confirmation: "Transcript copied"))
                }),
                .item(.init(title: "Last 5 min", subtitle: "Copy the last five minutes of the transcript",
                            systemImage: "clock.arrow.circlepath", isEnabled: !session.lines.isEmpty) {
                    copied.copy(.init(text: session.transcriptText(lastMinutes: 5),
                                      confirmation: "Last five minutes copied"))
                }),
            ]
        case .notes:
            return [
                .item(.init(title: "Copy notes", systemImage: BlitzSymbols.copyLink,
                            isEnabled: !session.notes.isEmpty || session.recap != nil || !session.marks.isEmpty) {
                    copied.copy(.init(text: session.notesText, confirmation: "Notes copied"))
                }),
            ]
        case .ask:
            return []
        }
    }
}

/// Notes of a call: summary, decisions, to-dos, open questions, the follow-up email, marked moments and what was
/// on screen. Shown in the Live Notes panel and with the recording in the library.
struct LiveCallNotesContent: View {
    struct Configuration {
        let notes: LiveCallNotes
        let followUpEmail: String?
        let marks: [LiveMark]
        let screenMoments: [ScreenMoment]
        let takeDirectory: URL?
        let copy: (String) -> Void
    }

    let configuration: Configuration
    private static let images = NSCache<NSURL, NSImage>()

    private static func image(_ url: URL) -> NSImage? {
        if let cached = images.object(forKey: url as NSURL) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        images.setObject(image, forKey: url as NSURL)
        return image
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !configuration.notes.summary.isEmpty {
                section("Summary") { bodyText(configuration.notes.summary) }
            }
            list("Decisions", configuration.notes.decisions)
            list("To-dos", configuration.notes.actionItems)
            list("Open questions", configuration.notes.openQuestions)
            if let email = configuration.followUpEmail, !email.isEmpty {
                section("Follow-up email") {
                    bodyText(email)
                    Button { configuration.copy(email) } label: { Label("Copy email", systemImage: BlitzSymbols.copyLink) }
                        .blitzButton(.quiet)
                }
            }
            if !configuration.marks.isEmpty {
                section("Marked moments") {
                    ForEach(configuration.marks) { mark in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(LiveCallSession.timestamp(mark.time)) · \(mark.title ?? "Marked moment")")
                                .font(BlitzType.captionEmphasis)
                                .foregroundStyle(BlitzUI.primaryText)
                            if let summary = mark.summary { caption(summary) }
                            thumbnail(mark.screenshot)
                        }
                    }
                }
            }
            if !configuration.screenMoments.isEmpty {
                section("On screen") {
                    ForEach(configuration.screenMoments.suffix(8).reversed()) { moment in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(LiveCallSession.timestamp(moment.time)) · \(moment.heading)")
                                .font(BlitzType.captionEmphasis)
                                .foregroundStyle(BlitzUI.primaryText)
                            if !moment.text.isEmpty { caption(moment.text).lineLimit(3) }
                            ForEach(moment.links, id: \.self) { link in
                                if let url = URL(string: link), url.scheme?.hasPrefix("http") == true {
                                    Link(link, destination: url).font(BlitzType.caption).lineLimit(1)
                                } else {
                                    caption(link).textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(BlitzType.section).foregroundStyle(BlitzUI.primaryText)
            content()
        }
    }

    @ViewBuilder
    private func list(_ title: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            section(title) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in bodyText("• \(item)") }
            }
        }
    }

    private func bodyText(_ text: String) -> some View {
        Text(text).font(BlitzType.body).foregroundStyle(BlitzUI.primaryText).textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func caption(_ text: String) -> Text {
        Text(text).font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
    }

    @ViewBuilder
    private func thumbnail(_ relativePath: String?) -> some View {
        if let relativePath, let directory = configuration.takeDirectory,
           let image = Self.image(directory.appendingPathComponent(relativePath)) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 240, maxHeight: 140, alignment: .leading)
                .clipShape(.rect(cornerRadius: BlitzUI.controlRadius, style: .continuous))
        }
    }
}

#Preview("Live notes · transcript") {
    LiveNotesView(session: .preview(), tab: .transcript)
        .frame(width: 360, height: 520)
}

#Preview("Live notes · notes") {
    LiveNotesView(session: .preview(), tab: .notes)
        .frame(width: 360, height: 520)
}

#Preview("Live notes · ask") {
    LiveNotesView(session: .preview(), tab: .ask)
        .frame(width: 360, height: 520)
}

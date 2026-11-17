import AppKit
import Foundation
import Observation

/// The transcript, running notes and screen context of the take being recorded, shown in the Live Notes panel and
/// served to agents over MCP. Lines appear about 15 s after they are said: speech is decoded from the backup audio
/// the recorders already write, so the take itself is never touched.
@MainActor
@Observable
final class LiveCallSession {
    static let shared = LiveCallSession()

    enum Status: Equatable {
        case idle
        case listening
        case finishing
        case finished
        case unavailable(String)
    }

    enum NotesStatus: Equatable {
        case waiting
        case updating
        case ready(Date)
        case unavailable(String)
    }

    enum RecapStatus: Equatable {
        case none
        case writing
        case ready
    }

    struct Answer: Equatable, Identifiable {
        let id: UUID
        let question: String
        var text: String
        var isAnswering: Bool
    }

    struct Line: Codable, Equatable, Identifiable, Sendable {
        let id: UUID
        let source: TranscriptWord.Source
        var start: Double
        var end: Double
        var text: String

        var speaker: String { source == .microphone ? "You" : "Call" }
    }

    struct StartRequest {
        let takeDirectory: URL
        let microphoneURL: URL?
        let systemAudioURL: URL?
        let language: TranscriptionLanguage
        let readsScreen: Bool
        /// Why this take can't be followed live, such as a recording mode that keeps no separate audio; nil when it can.
        let unavailableReason: String?
        /// Seconds recorded so far on the take timeline, which stops moving while paused.
        let timelineSeconds: @MainActor () -> Double
    }

    private(set) var status: Status = .idle
    private(set) var lines: [Line] = []
    private(set) var notes = LiveCallNotes.empty
    private(set) var notesStatus: NotesStatus = .waiting
    private(set) var screenMoments: [ScreenMoment] = []
    private(set) var language: String?
    private(set) var lastHeardAt: Date?
    private(set) var takeDirectory: URL?
    private(set) var marks: [LiveMark] = []
    private(set) var recap: LiveCallRecap?
    private(set) var recapStatus = RecapStatus.none
    private(set) var answers: [Answer] = []
    /// A short confirmation shown in place of the status, such as "Marked 12:34".
    let flash = TransientMessage()
    /// Whether the transcript and notes show under the recording controls; remembered between takes.
    var isShownInRecordingControls = UserDefaults.standard.object(forKey: LiveCallSession.shownKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(isShownInRecordingControls, forKey: Self.shownKey) }
    }
    private static let shownKey = "liveNotes.shownInRecordingControls"

    static let tickSeconds = 1.0
    static let notesEverySeconds = 120.0
    static let notesMinimumNewWords = 40
    static let glanceEverySeconds = 10.0
    static let lineJoinSeconds = 1.5
    /// A line is closed once it holds this much speech, so long monologues stay readable.
    static let lineSeconds = 30.0

    private let transcriber = LiveTranscriber()
    private var worker: Task<Void, Never>?
    private var notesTask: Task<Void, Never>?
    private var request: StartRequest?
    /// Microphone speech waits until the call is decoded through the same moment, so echo of the call is removed.
    private var heldMicrophone: [LiveTranscriber.Heard] = []
    private var recentCallWords: [TranscriptWord] = []
    private var hasCallAudio = false
    private var notedLineCount = 0
    private var notedMomentCount = 0
    private var lastNotesAt = 0.0
    private var lastGlanceAt = -Double.infinity
    private var lastGlanceTimeline = -1.0
    private var generation = 0
    private let markShortcut = GlobalHotKey(.init(keyCode: GlobalHotKey.markKeyCode,
                                                  modifiers: GlobalHotKey.controlOption))
    /// Folder in the take for screenshots of marked moments.
    static let assetsFolder = "live-notes"
    static let markMergeSeconds = 3.0

    func start(_ request: StartRequest) {
        worker?.cancel()
        notesTask?.cancel()
        generation += 1
        self.request = request
        lines = []
        notes = .empty
        screenMoments = []
        heldMicrophone = []
        recentCallWords = []
        hasCallAudio = request.systemAudioURL != nil
        notedLineCount = 0
        notedMomentCount = 0
        lastNotesAt = 0
        lastGlanceAt = -.infinity
        lastGlanceTimeline = -1
        lastHeardAt = nil
        marks = []
        recap = nil
        recapStatus = .none
        answers = []
        takeDirectory = request.takeDirectory
        language = request.language.whisperCode
        guard transcriber.isAvailable() else {
            status = .unavailable("Download a transcription model in Settings → Transcription to see the call live.")
            notesStatus = .waiting
            return
        }
        if let reason = request.unavailableReason {
            status = .unavailable(reason)
            notesStatus = .waiting
            return
        }
        switch LiveNotesWriter.availability() {
        case .available: notesStatus = .waiting
        case .unavailable(let reason): notesStatus = .unavailable(reason)
        }
        status = .listening
        markShortcut.register { LiveCallSession.shared.mark() }
        let tracks = [
            request.microphoneURL.map { LiveAudioFeed.Track(source: .microphone, audioURL: $0) },
            request.systemAudioURL.map { LiveAudioFeed.Track(source: .systemAudio, audioURL: $0) },
        ].compactMap { $0 }
        let generation = generation
        let requestedLanguage = request.language.whisperCode
        worker = Task { [weak self, transcriber] in
            await transcriber.begin(.init(tracks: tracks, language: requestedLanguage))
            while !Task.isCancelled {
                await self?.tick(.init(generation: generation, isFinal: false))
                try? await Task.sleep(for: .seconds(Self.tickSeconds))
            }
        }
    }

    /// Decodes what is left, updates the notes once more, writes the recap and saves everything beside the take.
    /// Returns the marked moments with their titles, for the project's chapters.
    @discardableResult
    func finish() async -> [LiveMark] {
        guard status == .listening else { return [] }
        status = .finishing
        markShortcut.unregister()
        worker?.cancel()
        worker = nil
        let generation = generation
        await tick(.init(generation: generation, isFinal: true))
        await transcriber.end()
        await notesTask?.value
        if lines.count > notedLineCount { await updateNotes(generation: generation) }
        guard generation == self.generation else { return [] }
        status = .finished
        save()
        if !lines.isEmpty, case .available = LiveNotesWriter.availability() { recapStatus = .writing }
        let wrapped = await LiveNotesWriter.wrapUp(.init(lines: lines, notes: notes, marks: marks,
                                                         terms: screenTerms, language: language))
        guard generation == self.generation else { return [] }
        marks = wrapped.marks.map { titled in
            var mark = titled
            mark.screenshot = mark.screenshot ?? marks.first { $0.id == titled.id }?.screenshot
            return mark
        }
        recap = wrapped.recap
        recapStatus = wrapped.recap == nil ? .none : .ready
        save()
        return marks
    }

    /// Marks this moment of the call: it becomes a titled moment in the notes and a chapter of the project, with a
    /// picture of the front window when the screen may be read.
    func mark() {
        guard status == .listening, let request else { return }
        let time = request.timelineSeconds()
        guard !marks.contains(where: { abs($0.time - time) < Self.markMergeSeconds }) else {
            flash.show("Already marked at \(Self.timestamp(time))")
            return
        }
        let mark = LiveMark(id: UUID(), time: time)
        marks.append(mark)
        flash.show("Marked \(Self.timestamp(time))")
        guard request.readsScreen, let frontmost = ScreenContextReader.frontmost(), let takeDirectory else { return }
        let generation = generation
        let relative = "\(Self.assetsFolder)/mark-\(Int(time)).jpg"
        Task { [weak self] in
            let seen = await ScreenContextReader.windowGlance(.init(processID: frontmost.processID, languages: []))
            guard let image = seen.image else { return }
            let url = takeDirectory.appendingPathComponent(relative)
            let saved = await Task.detached(priority: .utility) {
                ScreenContextReader.saveThumbnail(.init(image: image, url: url))
            }.value
            guard saved, let self, generation == self.generation,
                  let index = self.marks.firstIndex(where: { $0.id == mark.id }) else { return }
            self.marks[index].screenshot = relative
        }
    }

    /// Answers a question about the call on the Mac, as the answer is written.
    func ask(_ question: String) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        let id = UUID()
        answers.insert(Answer(id: id, question: question, text: "", isAnswering: true), at: 0)
        guard case .available = LiveNotesWriter.availability() else {
            updateAnswer(.init(id: id, text: "Answers need Apple Intelligence, turned on in System Settings.", done: true))
            return
        }
        let request = LiveNotesWriter.question(.init(
            question: question, lines: lines, notes: recap?.markdown ?? notes.markdown,
            screenMoments: screenMoments, terms: screenTerms
        ))
        Task { [weak self] in
            do {
                for try await text in LiveNotesWriter.answer(request) {
                    self?.updateAnswer(.init(id: id, text: text, done: false))
                }
                self?.updateAnswer(.init(id: id, text: nil, done: true))
            } catch {
                self?.updateAnswer(.init(id: id, text: "No answer: \(error.localizedDescription)", done: true))
            }
        }
    }

    private struct AnswerUpdate {
        let id: UUID
        let text: String?
        let done: Bool
    }

    private func updateAnswer(_ update: AnswerUpdate) {
        guard let index = answers.firstIndex(where: { $0.id == update.id }) else { return }
        if let text = update.text { answers[index].text = text }
        guard update.done else { return }
        answers[index].isAnswering = false
        if answers[index].text.isEmpty { answers[index].text = "No answer." }
    }

    private struct Tick {
        let generation: Int
        let isFinal: Bool
    }

    private func tick(_ tick: Tick) async {
        guard tick.generation == generation, let request else { return }
        do {
            let progress = try await transcriber.advance(.init(isFinal: tick.isFinal))
            guard tick.generation == generation else { return }
            if language == nil, let decided = progress.language { language = decided }
            receive(.init(progress: progress, isFinal: tick.isFinal, now: request.timelineSeconds()))
        } catch {
            CaptureLog.note("Live transcript: \(error.localizedDescription)")
        }
        let now = request.timelineSeconds()
        if request.readsScreen, !tick.isFinal, now - lastGlanceAt >= Self.glanceEverySeconds, now != lastGlanceTimeline {
            lastGlanceAt = now
            lastGlanceTimeline = now
            await glance(.init(generation: tick.generation, time: now))
        }
        if !tick.isFinal, notesTask == nil, now - lastNotesAt >= Self.notesEverySeconds,
           newWordCount >= Self.notesMinimumNewWords {
            lastNotesAt = now
            let generation = tick.generation
            notesTask = Task { [weak self] in
                await self?.updateNotes(generation: generation)
                self?.notesTask = nil
            }
        }
    }

    private struct Received {
        let progress: LiveTranscriber.Progress
        let isFinal: Bool
        let now: Double
    }

    /// Microphone speech is shown after this long even when no call audio arrived to compare it with.
    static let heldMicrophoneSeconds = 20.0

    private func receive(_ received: Received) {
        for speech in received.progress.heard {
            if speech.source == .microphone && hasCallAudio {
                heldMicrophone.append(speech)
            } else {
                recentCallWords += speech.words
                add(speech)
            }
        }
        let callThrough = received.progress.decodedThrough[.systemAudio] ?? 0
        let ready = heldMicrophone.filter {
            let end = $0.words.last?.endTime ?? 0
            return received.isFinal || end + LiveEchoFilter.windowSeconds <= callThrough
                || received.now - end >= Self.heldMicrophoneSeconds
        }
        heldMicrophone.removeAll { held in ready.contains { $0.words.first?.startTime == held.words.first?.startTime } }
        for speech in ready {
            let words = LiveEchoFilter.filtered(.init(microphone: speech.words, call: recentCallWords.filter {
                $0.endTime >= (speech.words.first?.startTime ?? 0) - LiveEchoFilter.windowSeconds
                    && $0.startTime <= (speech.words.last?.endTime ?? 0) + LiveEchoFilter.windowSeconds
            }))
            add(.init(source: speech.source, words: words))
        }
        let horizon = min(callThrough, heldMicrophone.compactMap { $0.words.first?.startTime }.min() ?? callThrough)
        recentCallWords.removeAll { $0.endTime < horizon - 30 }
    }

    private func add(_ heard: LiveTranscriber.Heard) {
        guard let first = heard.words.first, let last = heard.words.last else { return }
        let text = heard.words.map(\.text).joined(separator: " ")
        lastHeardAt = Date()
        let index = lines.firstIndex { $0.start > first.startTime } ?? lines.endIndex
        if index > 0, lines[index - 1].source == heard.source,
           first.startTime - lines[index - 1].end <= Self.lineJoinSeconds, index - 1 >= notedLineCount,
           last.endTime - lines[index - 1].start <= Self.lineSeconds {
            lines[index - 1].text += " " + text
            lines[index - 1].end = max(lines[index - 1].end, last.endTime)
        } else {
            lines.insert(Line(id: UUID(), source: heard.source, start: first.startTime, end: last.endTime, text: text),
                         at: index)
        }
    }

    private struct Glance {
        let generation: Int
        let time: Double
    }

    private func glance(_ glance: Glance) async {
        guard let frontmost = ScreenContextReader.frontmost() else { return }
        let languages = [language, "en"].compactMap { $0 }
        let seen = await ScreenContextReader.windowGlance(.init(processID: frontmost.processID, languages: languages))
        guard glance.generation == generation else { return }
        if let previous = screenMoments.last, ScreenContextReader.isSame(.init(
            previous: previous, app: frontmost.app, window: frontmost.window, text: seen.text
        )) { return }
        screenMoments.append(ScreenMoment(id: UUID(), time: glance.time, app: frontmost.app, window: frontmost.window,
                                          text: seen.text, links: ScreenContextReader.links(in: seen.text)))
    }

    private var newWordCount: Int {
        lines.dropFirst(notedLineCount).reduce(0) { $0 + $1.text.split(separator: " ").count }
    }

    private func updateNotes(generation: Int) async {
        guard case .available = LiveNotesWriter.availability() else { return }
        let lineCount = lines.count
        let momentCount = screenMoments.count
        let transcript = Self.text(Array(lines[notedLineCount..<lineCount]))
        let screen = screenMoments[notedMomentCount..<momentCount].map(Self.text).joined(separator: "\n")
        guard !transcript.isEmpty else { return }
        notesStatus = .updating
        do {
            let updated = try await LiveNotesWriter.updated(.init(
                previous: notes, transcript: transcript, screen: screen, terms: screenTerms, language: language
            ))
            guard generation == self.generation else { return }
            notes = updated
            notedLineCount = lineCount
            notedMomentCount = momentCount
            notesStatus = .ready(Date())
        } catch {
            guard generation == self.generation else { return }
            CaptureLog.note("Live notes: \(error.localizedDescription)")
            notesStatus = notes.isEmpty ? .waiting : .ready(Date())
        }
    }

    // MARK: - Text for copying, MCP and the saved notes

    nonisolated static func timestamp(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return total >= 3_600
            ? String(format: "%d:%02d:%02d", total / 3_600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }

    nonisolated static func text(_ lines: [Line]) -> String {
        lines.map { "[\(timestamp($0.start))] \($0.speaker): \($0.text)" }.joined(separator: "\n")
    }

    nonisolated static func text(_ moment: ScreenMoment) -> String {
        "[\(timestamp(moment.time))] \(moment.heading)" + (moment.text.isEmpty ? "" : ": \(moment.text)")
    }

    /// The transcript, or only its last minutes.
    func transcriptText(lastMinutes: Double?) -> String {
        guard let lastMinutes, let end = lines.last?.end else { return Self.text(lines) }
        return Self.text(lines.filter { $0.end >= end - lastMinutes * 60 })
    }

    var notesText: String {
        var parts: [String] = []
        if let recap { parts.append(recap.markdown) } else { parts.append(notes.markdown) }
        if !marks.isEmpty {
            parts.append("## Marked moments\n\n" + marks.map {
                "- [\(Self.timestamp($0.time))] \($0.title ?? "Marked moment")" + ($0.summary.map { ": \($0)" } ?? "")
            }.joined(separator: "\n"))
        }
        if !screenMoments.isEmpty {
            parts.append("## On screen\n\n" + screenMoments.map {
                "- " + Self.text($0) + ($0.links.isEmpty ? "" : " (\($0.links.joined(separator: ", ")))")
            }.joined(separator: "\n"))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// Names and terms read on screen during the call, so notes and answers spell them as written.
    private var screenTerms: [String] {
        ScreenContextReader.terms(in: screenMoments.map(\.text))
    }

    struct Snapshot: Codable, Sendable {
        let recording: Bool
        let language: String?
        let takeDirectory: String?
        let lines: [Line]
        let notes: LiveCallNotes
        let screenMoments: [ScreenMoment]
        let marks: [LiveMark]
        let recap: LiveCallRecap?
    }

    var snapshot: Snapshot {
        Snapshot(recording: status == .listening, language: language, takeDirectory: takeDirectory?.path,
                 lines: lines, notes: notes, screenMoments: screenMoments, marks: marks, recap: recap)
    }

    static let notesFileName = "live-notes.json"

    /// Saved beside the take, unless the take was deleted meanwhile.
    private func save() {
        guard let takeDirectory, FileManager.default.fileExists(atPath: takeDirectory.path), !lines.isEmpty else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let markdown = "# Call notes\n\n" + notesText + "\n\n## Transcript\n\n" + Self.text(lines) + "\n"
        do {
            try encoder.encode(snapshot).write(to: takeDirectory.appendingPathComponent(Self.notesFileName), options: .atomic)
            try Data(markdown.utf8).write(to: takeDirectory.appendingPathComponent("live-notes.md"), options: .atomic)
        } catch {
            CaptureLog.note("Live notes could not be saved: \(error.localizedDescription)")
        }
    }
}

#if DEBUG
extension LiveCallSession {
    /// A call in progress, for previews.
    static func preview() -> LiveCallSession {
        let session = LiveCallSession()
        session.status = .listening
        session.language = "fr"
        session.lines = [
            Line(id: UUID(), source: .systemAudio, start: 58, end: 72,
                 text: "Ok, bon. On fera à la fin des ateliers une passe sur le design, d'accord ? Ici, il y a écrit booking."),
            Line(id: UUID(), source: .microphone, start: 73, end: 79,
                 text: "Oui, mais Brandon m'a demandé de ne pas utiliser le design de la V2."),
            Line(id: UUID(), source: .systemAudio, start: 81, end: 95,
                 text: "Si je clique sur clôturer, j'aimerais qu'on parte directement sur l'upload du document."),
        ]
        session.notes = LiveCallNotes(
            summary: "Revue de l'écran de clôture des bookings et du design system à utiliser.",
            decisions: ["Garder le nouveau design system pour les boutons (0:19)"],
            actionItems: ["Ouvrir directement l'upload du document après « Clôturer » (1:21)"],
            openQuestions: ["Faut-il retirer de la liste les bookings déjà clôturés ? (3:16)"]
        )
        session.notesStatus = .ready(Date())
        session.screenMoments = [
            ScreenMoment(id: UUID(), time: 64, app: "Arc", window: "Booking V2 · Admin",
                         text: "Booking · Référence retrouvée · Rattacher un nouveau booking · Clôturer",
                         links: ["https://admin.example.com/bookings/6041", "LIN-482"]),
        ]
        session.marks = [
            LiveMark(id: UUID(), time: 76, title: "Ne pas utiliser le design de la V2",
                     summary: "Brandon a demandé de garder l'ancien design pour la validation de la PR."),
        ]
        session.answers = [
            Answer(id: UUID(), question: "Qu'est-ce qui se passe quand on clique sur Clôturer ?",
                   text: "Il veut arriver directement sur l'upload du document, avec le tonnage déjà saisi (1:21).",
                   isAnswering: false),
        ]
        return session
    }
}
#endif


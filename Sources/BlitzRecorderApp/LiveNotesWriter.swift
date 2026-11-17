import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct LiveCallNotes: Codable, Equatable, Sendable {
    var summary: String
    var decisions: [String]
    var actionItems: [String]
    var openQuestions: [String]

    static let empty = LiveCallNotes(summary: "", decisions: [], actionItems: [], openQuestions: [])

    var isEmpty: Bool {
        summary.isEmpty && decisions.isEmpty && actionItems.isEmpty && openQuestions.isEmpty
    }

    var markdown: String {
        var parts: [String] = []
        if !summary.isEmpty { parts.append("## Summary\n\n\(summary)") }
        for (title, items) in [("Decisions", decisions), ("To-dos", actionItems), ("Open questions", openQuestions)]
            where !items.isEmpty {
            parts.append("## \(title)\n\n" + items.map { "- \($0)" }.joined(separator: "\n"))
        }
        return parts.joined(separator: "\n\n")
    }
}

/// A moment the person recording marked during the call, with a title written after the call.
struct LiveMark: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    /// Seconds on the take timeline.
    let time: Double
    var title: String?
    var summary: String?
    /// Screenshot of the front window when it was marked, relative to the take folder.
    var screenshot: String?
}

/// Written once the recording stops, from the running notes and the marked moments.
struct LiveCallRecap: Codable, Equatable, Sendable {
    var summary: String
    var decisions: [String]
    var actionItems: [String]
    var openQuestions: [String]
    var followUpEmail: String

    var markdown: String {
        LiveCallNotes(summary: summary, decisions: decisions, actionItems: actionItems, openQuestions: openQuestions)
            .markdown + (followUpEmail.isEmpty ? "" : "\n\n## Follow-up email\n\n\(followUpEmail)")
    }
}

/// Keeps running notes of a call with the on-device Apple model, so nothing said leaves the Mac. The model reads
/// about 4 000 tokens, so each update reads the notes so far plus only what was said since, cut into parts.
enum LiveNotesWriter {
    enum Availability: Equatable {
        case available
        case unavailable(String)
    }

    struct Update: Sendable {
        let previous: LiveCallNotes
        let transcript: String
        let screen: String
        /// Names and terms read on screen, so the notes spell them as they are written.
        let terms: [String]
        let language: String?
    }

    static let transcriptCharacters = 4_500
    static let screenCharacters = 1_000

    static func availability() -> Availability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(.appleIntelligenceNotEnabled):
                return .unavailable("Turn on Apple Intelligence in System Settings to get notes.")
            case .unavailable(.modelNotReady):
                return .unavailable("Apple Intelligence is still getting ready. Notes start once it is.")
            case .unavailable:
                return .unavailable("This Mac can't write notes on device.")
            }
        }
        #endif
        return .unavailable("Notes need macOS 26 with Apple Intelligence.")
    }

    /// Splits what was said since the last notes into parts the model can read, newest last.
    static func parts(_ transcript: String) -> [String] {
        var parts: [String] = []
        var current = ""
        for line in transcript.split(separator: "\n", omittingEmptySubsequences: true) {
            if current.count + line.count > transcriptCharacters, !current.isEmpty {
                parts.append(current)
                current = ""
            }
            current += String(line.prefix(transcriptCharacters)) + "\n"
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }

    static func updated(_ update: Update) async throws -> LiveCallNotes {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            var notes = update.previous
            for (index, part) in parts(update.transcript).enumerated() {
                notes = try await write(.init(
                    previous: notes, transcript: part,
                    screen: index == 0 ? String(update.screen.suffix(screenCharacters)) : "",
                    terms: update.terms, language: update.language
                ))
            }
            return notes
        }
        #endif
        return update.previous
    }

    static func termsLine(_ terms: [String]) -> String {
        terms.isEmpty ? "" : "\n\nNames and terms seen on screen, spelled as written: \(terms.joined(separator: ", "))"
    }

    struct MomentRequest: Sendable {
        let transcript: String
        let terms: [String]
        let language: String?
    }

    struct MomentTitle: Sendable {
        let title: String
        let summary: String
    }

    /// A short title and one sentence for a marked moment, from what was said around it.
    static func momentTitle(_ request: MomentRequest) async throws -> MomentTitle? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let session = LanguageModelSession(instructions: """
                You name a moment the person recording marked in a call, from what was said around it.
                Write in \(languageName(request.language)). Use only what the transcript says.
                """)
            let draft = try await session.respond(
                to: "Transcript around the marked moment:\n\(request.transcript.prefix(transcriptCharacters))"
                    + termsLine(request.terms) + "\n\nName this moment.",
                generating: MomentDraft.self
            ).content
            return MomentTitle(title: draft.title, summary: draft.summary)
        }
        #endif
        return nil
    }

    struct RecapRequest: Sendable {
        let notes: LiveCallNotes
        let moments: [String]
        let ending: String
        let terms: [String]
        let language: String?
    }

    /// The recap of the whole call: the running notes, the marked moments and the last minutes, rewritten once.
    static func recap(_ request: RecapRequest) async throws -> LiveCallRecap? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let session = LanguageModelSession(instructions: """
                You write the recap of a recorded call for the person who recorded it.
                Write everything in \(languageName(request.language)).
                Use only what the notes and transcript show. Never invent names, numbers, dates or decisions.
                "You" is the person recording; "Call" is the other side of the call.
                """)
            let moments = request.moments.isEmpty ? "" : "\n\nMoments marked during the call:\n"
                + request.moments.joined(separator: "\n")
            let draft = try await session.respond(
                to: "Running notes of the call:\n\(request.notes.markdown)\(moments)\n\nEnd of the call:\n"
                    + String(request.ending.suffix(transcriptCharacters / 2)) + termsLine(request.terms)
                    + "\n\nWrite the recap and a short follow-up email from You to the other side.",
                generating: RecapDraft.self
            ).content
            return LiveCallRecap(summary: draft.summary, decisions: draft.decisions, actionItems: draft.actionItems,
                                 openQuestions: draft.openQuestions, followUpEmail: draft.followUpEmail)
        }
        #endif
        return nil
    }

    struct Question: Sendable {
        let question: String
        let notes: String
        let transcript: String
        let screen: String
        let terms: [String]
    }

    /// Answers a question about the call as the answer is written, from the notes and the parts of the transcript
    /// that share words with the question.
    static func answer(_ question: Question) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                #if canImport(FoundationModels)
                if #available(macOS 26.0, *) {
                    do {
                        let session = LanguageModelSession(instructions: """
                            You answer questions about a call that is being recorded, for the person recording it.
                            Answer directly in the language of the question, in one to three sentences. Never talk about
                            yourself.
                            Use only the notes, transcript and screen below, and give the time like (12:30) when you
                            can. Say who said it: "You" is the person asking, "Call" is the other side of the call, and
                            a name mentioned in the transcript is someone they talked about.
                            If the transcript doesn't say, answer that it wasn't mentioned.
                            """)
                        let screen = question.screen.isEmpty ? "" : "\n\nOn screen:\n\(question.screen)"
                        let stream = session.streamResponse(
                            to: "Notes:\n\(question.notes.isEmpty ? "None yet." : question.notes)\n\n"
                                + "Transcript:\n\(question.transcript)\(screen)" + termsLine(question.terms)
                                + "\n\nQuestion: \(question.question)"
                        )
                        for try await snapshot in stream { continuation.yield(snapshot.content) }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                    return
                }
                #endif
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    struct WrapUp: Sendable {
        let lines: [LiveCallSession.Line]
        let notes: LiveCallNotes
        let marks: [LiveMark]
        let terms: [String]
        let language: String?
    }

    struct WrappedUp: Sendable {
        let marks: [LiveMark]
        let recap: LiveCallRecap?
    }

    static let momentBeforeSeconds = 45.0
    static let momentAfterSeconds = 30.0
    static let recapEndingSeconds = 180.0
    static let maximumTitledMarks = 12

    /// Once the call ends: titles each marked moment from what was said around it, then writes the recap of the
    /// whole call. Marks that could not be titled keep no title; the recap is nil when the model is unavailable.
    static func wrapUp(_ wrapUp: WrapUp) async -> WrappedUp {
        guard !wrapUp.lines.isEmpty, case .available = availability() else {
            return WrappedUp(marks: wrapUp.marks, recap: nil)
        }
        var marks = wrapUp.marks
        for index in marks.indices.prefix(maximumTitledMarks) {
            let time = marks[index].time
            let around = LiveCallSession.text(wrapUp.lines.filter {
                $0.end >= time - momentBeforeSeconds && $0.start <= time + momentAfterSeconds
            })
            guard !around.isEmpty, let named = try? await momentTitle(.init(
                transcript: around, terms: wrapUp.terms, language: wrapUp.language
            )) else { continue }
            marks[index].title = named.title
            marks[index].summary = named.summary
        }
        let end = wrapUp.lines.last?.end ?? 0
        let ending = LiveCallSession.text(wrapUp.lines.filter { $0.end >= end - recapEndingSeconds })
        let moments = marks.map { "[\(LiveCallSession.timestamp($0.time))] \($0.title ?? "Marked moment")" }
        do {
            let written = try await recap(.init(notes: wrapUp.notes, moments: moments, ending: ending,
                                                terms: wrapUp.terms, language: wrapUp.language))
            return WrappedUp(marks: marks, recap: written)
        } catch {
            CaptureLog.note("Call recap: \(error.localizedDescription)")
            return WrappedUp(marks: marks, recap: nil)
        }
    }

    struct QuestionSource: Sendable {
        let question: String
        let lines: [LiveCallSession.Line]
        let notes: String
        let screenMoments: [ScreenMoment]
        let terms: [String]
    }

    static let answerLineLimit = 45
    static let answerRecentLines = 12
    static let answerCharacters = 4_000

    /// What the model reads to answer: the lines that share the most words with the question plus the last few,
    /// in call order, the notes, and the latest screens.
    static func question(_ source: QuestionSource) -> Question {
        let wanted = Set(keywords(source.question))
        let best = source.lines.indices
            .map { (index: $0, score: Set(keywords(source.lines[$0].text)).intersection(wanted).count) }
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .prefix(answerLineLimit - answerRecentLines)
            .map(\.index)
        let chosen = Set(best + source.lines.indices.suffix(answerRecentLines)).sorted().map { source.lines[$0] }
        return Question(
            question: source.question,
            notes: source.notes,
            transcript: String(LiveCallSession.text(chosen).prefix(answerCharacters)),
            screen: source.screenMoments.suffix(6).map(LiveCallSession.text).joined(separator: "\n"),
            terms: source.terms
        )
    }

    static func keywords(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 4 }
    }

    static func languageName(_ code: String?) -> String {
        code.flatMap { Locale(identifier: "en").localizedString(forLanguageCode: $0) } ?? "the language of the call"
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    @Generable
    struct Draft {
        @Guide(description: "Two to four sentences on what the call has covered so far.")
        let summary: String
        @Guide(description: "Decisions taken in the call, most important first, each ending with its time like (12:30).",
               .maximumCount(6))
        let decisions: [String]
        @Guide(description: "Things someone said they will do, with who does it when known, each ending with its time.",
               .maximumCount(6))
        let actionItems: [String]
        @Guide(description: "Questions raised and not answered yet, each ending with its time.", .maximumCount(5))
        let openQuestions: [String]
    }

    @available(macOS 26.0, *)
    @Generable
    struct MomentDraft {
        @Guide(description: "A title of at most eight words for what this moment is about.")
        let title: String
        @Guide(description: "One sentence on what was said or decided at this moment.")
        let summary: String
    }

    @available(macOS 26.0, *)
    @Generable
    struct RecapDraft {
        @Guide(description: "Four to six sentences on what the call covered and where it ended.")
        let summary: String
        @Guide(description: "Decisions taken, most important first, each ending with its time like (12:30).", .maximumCount(8))
        let decisions: [String]
        @Guide(description: "To-dos written as 'Who: what', each ending with its time. Use You or Call when the name is unknown.",
               .maximumCount(8))
        let actionItems: [String]
        @Guide(description: "Questions still open at the end of the call.", .maximumCount(6))
        let openQuestions: [String]
        @Guide(description: "A short, friendly follow-up email from You listing the decisions and next steps, without a subject line.")
        let followUpEmail: String
    }

    @available(macOS 26.0, *)
    private static func write(_ update: Update) async throws -> LiveCallNotes {
        let language = languageName(update.language)
        let session = LanguageModelSession(instructions: """
            You keep running notes of a recorded call for the person recording it.
            Write everything in \(language).
            Use only what the transcript and the screen show. Never invent names, numbers, dates or decisions.
            Keep the earlier notes unless the new part changes or completes them.
            "You" is the person recording; "Call" is the other side of the call.
            """)
        let previous = update.previous.isEmpty ? "None yet." : update.previous.markdown
        let screen = update.screen.isEmpty ? "" : "\n\nWhat was on screen meanwhile:\n\(update.screen)"
        let draft = try await session.respond(
            to: "Notes so far:\n\(previous)\(screen)\n\nNew part of the call:\n\(update.transcript)"
                + termsLine(update.terms) + "\n\nUpdate the notes.",
            generating: Draft.self
        ).content
        return LiveCallNotes(summary: draft.summary, decisions: draft.decisions,
                             actionItems: draft.actionItems, openQuestions: draft.openQuestions)
    }
    #endif
}

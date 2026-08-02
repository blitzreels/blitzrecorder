import Foundation
import Speech

#if canImport(FoundationModels)
import FoundationModels
#endif

final class SpeechTranscriber {
    func transcribe(audioURL: URL) async throws -> String {
        let authorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard authorizationStatus == .authorized,
              let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_US")),
              recognizer.isAvailable else {
            throw RecorderError.speechUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            let task = recognizer.recognitionTask(with: request) { result, error in
                guard !didResume else { return }

                if let result, result.isFinal {
                    didResume = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                    return
                }

                if let error {
                    didResume = true
                    continuation.resume(throwing: error)
                }
            }

            if task.isCancelled, !didResume {
                didResume = true
                continuation.resume(throwing: RecorderError.speechUnavailable)
            }
        }
    }
}

struct TitleGenerator {
    struct TranscriptTitleRequest {
        let transcript: String
    }

    private struct OllamaGenerationRequest {
        let model: String
        let prompt: String
    }

    private struct OllamaTitleRequest {
        let model: String
        let transcript: String
    }

    struct TopicBriefPromptRequest {
        let chunk: String
        let index: Int
        let total: Int
    }

    func title(
        _ request: TranscriptTitleRequest
    ) async throws -> String {
        let transcript = request.transcript.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard Self.hasUsableTitleSignal(transcript) else {
            throw TranscriptTitleGenerationError.transcriptTooShort
        }

        var lastError: Error?

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            do {
                let title = try await foundationModelTitle(for: transcript)
                if let sanitized = Self.sanitizeGeneratedTitle(title) {
                    return sanitized
                }
            } catch {
                lastError = error
            }
        }
        #endif

        for model in ["qwen2.5:0.5b", "llama3.2:1b", "gemma3:1b"] {
            do {
                let generated = try await ollamaTitle(
                    OllamaTitleRequest(
                        model: model,
                        transcript: transcript
                    )
                )
                if let title = Self.sanitizeGeneratedTitle(generated) {
                    return title
                }
            } catch {
                lastError = error
            }
        }

        if let fallbackTitle = Self.fallbackTitle(from: transcript) {
            return fallbackTitle
        }

        if let lastError {
            throw lastError
        }
        throw TranscriptTitleGenerationError.modelUnavailable
    }

    func titleSlug(for transcript: String) async -> String? {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.hasUsableTitleSignal(trimmed) else {
            return nil
        }

        if let generatedTitle = try? await title(
            TranscriptTitleRequest(transcript: trimmed)
        ),
           let slug = Self.sanitizeSlug(generatedTitle),
           Self.hasUsableTitleSignal(slug) {
            return slug
        }

        return Self.fallbackSlug(from: trimmed)
    }

    private func ollamaTitle(
        _ request: OllamaTitleRequest
    ) async throws -> String {
        let chunks = Self.transcriptChunks(request.transcript)
        guard chunks.count > 1 else {
            return try await ollamaGenerate(OllamaGenerationRequest(
                model: request.model,
                prompt: Self.titlePrompt(for: request.transcript)
            ))
        }

        var briefs: [String] = []
        for (index, chunk) in chunks.enumerated() {
            briefs.append(try await ollamaGenerate(OllamaGenerationRequest(
                model: request.model,
                prompt: Self.topicBriefPrompt(TopicBriefPromptRequest(
                    chunk: chunk,
                    index: index,
                    total: chunks.count
                ))
            )))
        }
        return try await ollamaGenerate(OllamaGenerationRequest(
            model: request.model,
            prompt: Self.titleFromBriefsPrompt(briefs)
        ))
    }

    private func ollamaGenerate(
        _ request: OllamaGenerationRequest
    ) async throws -> String {
        guard let url = URL(string: "http://127.0.0.1:11434/api/generate") else {
            throw TranscriptTitleGenerationError.modelUnavailable
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 6
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = OllamaGenerateRequest(
            model: request.model,
            prompt: request.prompt,
            stream: false
        )
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let generated = try? JSONDecoder().decode(OllamaGenerateResponse.self, from: data).response else {
            throw TranscriptTitleGenerationError.modelUnavailable
        }

        return generated
    }

    static func sanitizeGeneratedTitle(
        _ value: String
    ) -> String? {
        var title = value
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""

        for prefix in ["Title:", "Suggested title:", "Video title:"] {
            if title.lowercased().hasPrefix(prefix.lowercased()) {
                title = String(title.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        title = title.trimmingCharacters(
            in: CharacterSet(charactersIn: "\"'`*_# ")
        )
        title = title.trimmingCharacters(
            in: CharacterSet(charactersIn: ".!?:;-")
        )
        let words = title
            .split(whereSeparator: \.isWhitespace)
            .prefix(10)
        title = words.joined(separator: " ")
        if title.count > 96 {
            title = String(title.prefix(96))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard hasUsableTitleSignal(title) else {
            return nil
        }
        return title
    }

    static func transcriptChunks(
        _ transcript: String
    ) -> [String] {
        let maximumChunkCharacters = 10_000
        guard transcript.count > maximumChunkCharacters else { return [transcript] }

        var chunks: [String] = []
        var start = transcript.startIndex
        while start < transcript.endIndex {
            let end = transcript.index(
                start,
                offsetBy: min(
                    maximumChunkCharacters,
                    transcript.distance(from: start, to: transcript.endIndex)
                )
            )
            chunks.append(String(transcript[start..<end]))
            start = end
        }
        return chunks
    }

    static func fallbackTitle(
        from transcript: String
    ) -> String? {
        let stopWords: Set<String> = [
            "about", "after", "again", "also", "and", "are", "because", "but",
            "for", "from", "have", "how", "into", "just", "like", "that", "the",
            "this", "today", "using", "was", "were", "with", "you", "your"
        ]
        var counts: [String: Int] = [:]
        var firstPositions: [String: Int] = [:]
        let candidates = transcript
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { word in
                word.count > 2 && !stopWords.contains(word.lowercased())
            }
        for (index, word) in candidates.enumerated() {
            let normalized = word.lowercased()
            counts[normalized, default: 0] += 1
            if firstPositions[normalized] == nil {
                firstPositions[normalized] = index
            }
        }
        let words = counts.keys.sorted { lhs, rhs in
            let lhsCount = counts[lhs, default: 0]
            let rhsCount = counts[rhs, default: 0]
            if lhsCount != rhsCount {
                return lhsCount > rhsCount
            }
            return firstPositions[lhs, default: 0] < firstPositions[rhs, default: 0]
        }.prefix(7)
        guard words.count >= 3 else { return nil }
        let title = words.joined(separator: " ")
        return title.prefix(1).uppercased() + title.dropFirst()
    }

    static func fallbackSlug(
        from transcript: String
    ) -> String? {
        guard let title = fallbackTitle(from: transcript) else { return nil }
        return sanitizeSlug(title)
    }

    static func topicBriefPrompt(
        _ request: TopicBriefPromptRequest
    ) -> String {
        """
        This is part \(request.index + 1) of \(request.total) from one recording transcript.
        Identify the concrete subjects, decisions, and repeated themes in this part.
        Return a compact factual brief in the transcript's language.

        Transcript part:
        \(request.chunk)
        """
    }

    static func titleFromBriefsPrompt(
        _ briefs: [String]
    ) -> String {
        let joinedBriefs = briefs.enumerated().map { index, brief in
            "[Part \(index + 1)]\n\(brief)"
        }.joined(separator: "\n\n")
        return """
        These briefs cover every consecutive part of one recording transcript.
        Identify the main subject across the complete recording.
        Return one concise, specific video title in the transcript's language.
        Use 4 to 10 words.
        Do not use quotes, markdown, a filename slug, or generic phrases.
        Return only the title.

        Full-recording briefs:
        \(joinedBriefs)
        """
    }

    private static func titlePrompt(
        for transcript: String
    ) -> String {
        """
        Read this recording transcript and identify its main subject.
        Return one concise, specific video title in the transcript's language.
        Use 4 to 10 words.
        Do not use quotes, markdown, a filename slug, or generic phrases.
        Return only the title.

        Transcript:
        \(transcript)
        """
    }

    private static func sanitizeSlug(
        _ value: String
    ) -> String? {
        let lowercased = value.lowercased()
        let parts = lowercased
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        let slug = parts.joined(separator: "-")
        if slug.isEmpty {
            return nil
        }
        return String(slug.prefix(72)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func hasUsableTitleSignal(_ value: String) -> Bool {
        let fillerWords: Set<String> = [
            "ah", "er", "hm", "hmm", "okay", "test", "testing", "thank", "thanks", "uh", "um", "yeah", "yes", "you"
        ]
        let words = value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let meaningfulWords = words.filter { word in
            word.count > 2 && !fillerWords.contains(word)
        }
        return meaningfulWords.count >= 3
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func foundationModelTitle(
        for transcript: String
    ) async throws -> String {
        let model = SystemLanguageModel.default
        guard model.availability == .available else {
            throw TranscriptTitleGenerationError.modelUnavailable
        }

        let chunks = Self.transcriptChunks(transcript)
        guard chunks.count > 1 else {
            let session = LanguageModelSession(
                model: model,
                instructions: Self.titleInstructions
            )
            return try await session.respond(
                to: Self.titlePrompt(for: transcript)
            ).content
        }

        var briefs: [String] = []
        for (index, chunk) in chunks.enumerated() {
            let session = LanguageModelSession(
                model: model,
                instructions: """
                Extract a compact factual topic brief from one transcript part.
                Preserve the transcript's language and use at most 80 words.
                """
            )
            briefs.append(try await session.respond(
                to: Self.topicBriefPrompt(TopicBriefPromptRequest(
                    chunk: chunk,
                    index: index,
                    total: chunks.count
                ))
            ).content)
        }

        let finalSession = LanguageModelSession(
            model: model,
            instructions: Self.titleInstructions
        )
        return try await finalSession.respond(
            to: Self.titleFromBriefsPrompt(briefs)
        ).content
    }

    private static let titleInstructions = """
    You create concise, accurate titles for screen recordings.
    Base the title on the main subject discussed throughout the complete transcript.
    Preserve the transcript's language.
    """
    #endif
}

enum TranscriptTitleGenerationError: LocalizedError {
    case transcriptTooShort
    case modelUnavailable

    var errorDescription: String? {
        switch self {
        case .transcriptTooShort:
            return "The transcript is too short to generate a useful title."
        case .modelUnavailable:
            return "No local AI model is available for title generation."
        }
    }
}

private struct OllamaGenerateRequest: Encodable {
    let model: String
    let prompt: String
    let stream: Bool
}

private struct OllamaGenerateResponse: Decodable {
    let response: String
}

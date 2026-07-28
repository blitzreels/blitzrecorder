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
                let generated = try await ollamaGenerate(
                    OllamaGenerationRequest(
                        model: model,
                        prompt: Self.titlePrompt(for: transcript)
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

        for model in ["qwen2.5:0.5b", "llama3.2:1b", "gemma3:1b"] {
            let prompt = """
            Create a short YouTube filename slug from this transcript.
            Rules:
            - 3 to 8 words
            - lowercase
            - hyphen-separated
            - no quotes
            - no extension

            Transcript:
            \(String(trimmed.prefix(2_800)))
            """
            if let generated = try? await ollamaGenerate(
                OllamaGenerationRequest(model: model, prompt: prompt)
            ),
               let slug = Self.sanitizeSlug(generated),
               Self.hasUsableTitleSignal(slug) {
                return slug
            }
        }

        return fallbackSlug(from: trimmed)
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

    private func fallbackSlug(from transcript: String) -> String? {
        let stopWords: Set<String> = [
            "about", "after", "again", "also", "and", "because", "but", "for", "from",
            "have", "into", "just", "like", "that", "the", "this", "with", "you", "your"
        ]
        let words = transcript
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }

        guard words.count >= 3 else {
            return nil
        }
        return Self.sanitizeSlug(words.prefix(7).joined(separator: "-"))
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

    static func condensedTranscript(
        _ transcript: String
    ) -> String {
        let limit = 6_000
        guard transcript.count > limit else { return transcript }

        let head = String(transcript.prefix(3_000))
        let tail = String(transcript.suffix(1_500))
        let middleStart = transcript.index(
            transcript.startIndex,
            offsetBy: max(0, transcript.count / 2 - 750)
        )
        let middleEnd = transcript.index(
            middleStart,
            offsetBy: min(1_500, transcript.distance(
                from: middleStart,
                to: transcript.endIndex
            ))
        )
        let middle = String(transcript[middleStart..<middleEnd])
        return "\(head)\n\n[Middle]\n\(middle)\n\n[End]\n\(tail)"
    }

    static func fallbackTitle(
        from transcript: String
    ) -> String? {
        let stopWords: Set<String> = [
            "about", "after", "again", "also", "and", "are", "because", "but",
            "for", "from", "have", "how", "into", "just", "like", "that", "the",
            "this", "today", "using", "was", "were", "with", "you", "your"
        ]
        let words = transcript
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { word in
                word.count > 2 && !stopWords.contains(word.lowercased())
            }
            .prefix(7)
        guard words.count >= 3 else { return nil }
        let title = words.joined(separator: " ")
        return title.prefix(1).uppercased() + title.dropFirst()
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
        \(condensedTranscript(transcript))
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
        let session = LanguageModelSession(
            model: model,
            instructions: """
            You create concise, accurate titles for screen recordings.
            Base the title on the main subject discussed throughout the transcript.
            Preserve the transcript's language.
            """
        )
        return try await session.respond(
            to: Self.titlePrompt(for: transcript)
        ).content
    }
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

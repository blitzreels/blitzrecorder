import Foundation
import Speech

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
    func titleSlug(for transcript: String) async -> String? {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.hasUsableTitleSignal(trimmed) else {
            return nil
        }

        for model in ["qwen2.5:0.5b", "llama3.2:1b", "gemma3:1b"] {
            if let slug = try? await ollamaSlug(model: model, transcript: trimmed),
               Self.hasUsableTitleSignal(slug) {
                return slug
            }
        }

        return fallbackSlug(from: trimmed)
    }

    private func ollamaSlug(model: String, transcript: String) async throws -> String {
        guard let url = URL(string: "http://127.0.0.1:11434/api/generate") else {
            return ""
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 6
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let clippedTranscript = String(transcript.prefix(2_800))
        let body = OllamaGenerateRequest(
            model: model,
            prompt: """
            Create a short YouTube filename slug from this transcript.
            Rules:
            - 3 to 8 words
            - lowercase
            - hyphen-separated
            - no quotes
            - no extension

            Transcript:
            \(clippedTranscript)
            """,
            stream: false
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let generated = try? JSONDecoder().decode(OllamaGenerateResponse.self, from: data).response else {
            return ""
        }

        return sanitize(generated)
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
        return sanitize(words.prefix(7).joined(separator: "-"))
    }

    private func sanitize(_ value: String) -> String {
        let lowercased = value.lowercased()
        let parts = lowercased
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        let slug = parts.joined(separator: "-")
        if slug.isEmpty {
            return ""
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
}

private struct OllamaGenerateRequest: Encodable {
    let model: String
    let prompt: String
    let stream: Bool
}

private struct OllamaGenerateResponse: Decodable {
    let response: String
}

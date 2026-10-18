import Foundation
import NaturalLanguage
import XCTest
@testable import BlitzRecorderApp

final class CallTranscriptionBenchmarkTests: XCTestCase {
    struct Manifest: Decodable {
        let model: String
        let outputDirectory: String
        let cases: [Case]
    }

    struct Case: Decodable {
        let name: String
        let projectPath: String
        let language: String
        let speakers: Int
        let minimumWords: Int
        let forbiddenPhrases: [String]
        let forbiddenMicrophoneWords: [String]
        let remoteAnchors: [String]
        let speakerMode: String?
        let requiredPhrases: [String]?
        let speakerGroups: [[String]]?
        let requestedLanguage: String?
        let reviewAmbiguousSpeakers: Bool?
    }

    struct Result: Encodable {
        let name: String
        let seconds: Double
        let language: String
        let speakers: Int
        let words: Int
        let violations: [String]
        let reviewIssues: Int
        let reviewWarnings: [String]
    }

    func testUpdateInstalledSpeechAssetsWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["BLITZRECORDER_UPDATE_SPEECH_ASSETS"] == "1" else {
            throw XCTSkip("Enable the explicit installed-model update to prepare speech detection assets.")
        }
        try await LocalTranscriptionEngine().downloadModels(.init(model: .whisperLarge, onUpdate: { update in
            print("SPEECH_ASSETS \(update.phase) \(update.fractionCompleted)")
        }))
        XCTAssertTrue(LocalTranscriptionModelStore().isInstalled(.whisperLarge))
    }

    func testRawCallCorpusWhenRequested() async throws {
        guard let path = ProcessInfo.processInfo.environment["BLITZRECORDER_CALL_BENCHMARK"] else {
            throw XCTSkip("Set a raw-audio corpus manifest to evaluate call transcription.")
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let model = try XCTUnwrap(TranscriptionSpeechModel(rawValue: manifest.model))
        XCTAssertTrue(LocalTranscriptionModelStore().isInstalled(model))
        let output = URL(fileURLWithPath: manifest.outputDirectory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let engine = LocalTranscriptionEngine()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var results: [Result] = []
        for entry in manifest.cases {
            let projectURL = URL(fileURLWithPath: entry.projectPath)
            let project = try TakeFileStore().loadRecordingProject(at: projectURL)
            guard TranscriptArtifactStore().locations(for: project).jsonURL.deletingLastPathComponent()
                    == projectURL.deletingLastPathComponent() else {
                XCTFail("Benchmark inputs must write only to a staged project copy")
                throw CocoaError(.fileWriteNoPermission)
            }
            let started = Date()
            let transcript = try await engine.transcribe(.init(
                source: .project(projectURL), model: model,
                language: entry.requestedLanguage.flatMap(TranscriptionLanguage.init(rawValue:)) ?? .automatic,
                speakerCount: entry.speakerMode.flatMap(TranscriptionSpeakerCount.init(rawValue:)) ?? .automatic,
                onUpdate: { _ in }
            ))
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(transcript.text)
            let language = recognizer.dominantLanguage?.rawValue ?? "none"
            let normalized = Self.normalized(transcript.text)
            var violations: [String] = []
            if !["none", "mixed"].contains(entry.language), language != entry.language {
                violations.append("wrong language: \(language)")
            }
            if transcript.speakerCount != entry.speakers { violations.append("speaker count: \(transcript.speakerCount)") }
            if transcript.words?.count ?? 0 < entry.minimumWords { violations.append("missing speech") }
            if entry.language == "none", !(transcript.words ?? []).isEmpty { violations.append("invented speech") }
            for phrase in entry.forbiddenPhrases where normalized.contains(Self.normalized(phrase)) {
                violations.append("unsupported phrase: \(phrase)")
            }
            for phrase in entry.requiredPhrases ?? [] where !normalized.contains(Self.normalized(phrase)) {
                violations.append("missing source-language phrase: \(phrase)")
            }
            let microphoneIDs = Set(transcript.speakers.filter { $0.name == "You" }.map(\.id))
            for word in transcript.words ?? [] where microphoneIDs.contains(word.speakerID ?? "") {
                if entry.forbiddenMicrophoneWords.contains(Self.normalized(word.text)) {
                    violations.append("remote word assigned to microphone: \(word.text)")
                }
            }
            for anchor in entry.remoteAnchors {
                let word = transcript.words?.first { Self.normalized($0.text) == Self.normalized(anchor) }
                if word == nil || microphoneIDs.contains(word?.speakerID ?? "") {
                    violations.append("remote anchor missing or misassigned: \(anchor)")
                }
            }
            var groupIDs: [String] = []
            for group in entry.speakerGroups ?? [] {
                let matching = (transcript.words ?? []).filter { group.contains(Self.normalized($0.text)) }
                let ids = Set(matching.compactMap(\.speakerID))
                if ids.count != 1 || ids.contains(RecordingTranscript.Speaker.unassignedID) {
                    violations.append("speaker anchors missing or split: \(group.joined(separator: ", "))")
                } else if let id = ids.first { groupIDs.append(id) }
            }
            if Set(groupIDs).count != groupIDs.count { violations.append("distinct voices merged") }
            if !transcript.segments.allSatisfy({
                $0.startTime >= 0 && $0.endTime >= $0.startTime && $0.endTime <= transcript.duration + 0.01
            }) { violations.append("invalid timing") }
            var reviewWarnings: [String] = []
            if entry.reviewAmbiguousSpeakers == true {
                let flagged = transcript.quality?.issues.contains {
                    [.unstableSpeaker, .similarVoices].contains($0.kind)
                } == true
                if !flagged { violations.append("ambiguous voice assignment was presented without review") }
                if flagged {
                    reviewWarnings = violations.filter {
                        $0.hasPrefix("speaker anchors missing or split") || $0 == "distinct voices merged"
                    }
                    violations.removeAll { reviewWarnings.contains($0) }
                }
            }
            let result = Result(name: entry.name, seconds: Date().timeIntervalSince(started), language: language,
                                speakers: transcript.speakerCount, words: transcript.words?.count ?? 0,
                                violations: violations, reviewIssues: transcript.quality?.issues.count ?? 0,
                                reviewWarnings: reviewWarnings)
            results.append(result)
            try encoder.encode(transcript).write(to: output.appendingPathComponent(entry.name + "-transcript.json"), options: .atomic)
            try encoder.encode(results).write(to: output.appendingPathComponent("results.json"), options: .atomic)
            print("CALL_BENCHMARK \(entry.name): \(violations.isEmpty ? "PASS" : violations.joined(separator: "; "))")
            fflush(stdout)
            XCTAssertTrue(violations.isEmpty, "\(entry.name): \(violations.joined(separator: "; "))")
        }
    }

    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
    }
}

import Foundation
import XCTest
@testable import BlitzRecorderApp

final class CallTranscriptReliabilityTests: XCTestCase {
    func testSilenceHasNoInventedSpeaker() {
        let transcript = assemble(.init(words: [], intervals: []))
        XCTAssertTrue(transcript.speakers.isEmpty)
        XCTAssertTrue(transcript.segments.isEmpty)
    }

    func testDistantAmbiguousVoiceStaysUnassigned() {
        let transcript = assemble(.init(words: [.init(text: "Hello", startTime: 15, endTime: 16,
                                               confidence: 0.9, source: .systemAudio)], intervals: [
            .init(speakerID: "sys-a", startTime: 0, endTime: 2, embedding: [1, 0]),
            .init(speakerID: "sys-b", startTime: 25, endTime: 28, embedding: [0, 1])
        ]))
        XCTAssertEqual(transcript.words?.first?.speakerID, RecordingTranscript.Speaker.unassignedID)
        XCTAssertEqual(transcript.speakerName(for: RecordingTranscript.Speaker.unassignedID), "Unassigned speaker")
    }

    func testSpeakerRepairUsesSavedSourceDuringOverlappingSpeech() throws {
        let words: [TranscriptWord] = [
            .init(text: "Local", startTime: 1, endTime: 1.4, confidence: 0.9, source: .microphone),
            .init(text: "Remote", startTime: 1.1, endTime: 1.5, confidence: 0.9, source: .systemAudio)
        ]
        let intervals: [DiarizedInterval] = [
            .init(speakerID: "mic-a", startTime: 0, endTime: 4, embedding: [1, 0]),
            .init(speakerID: "sys-b", startTime: 0, endTime: 4, embedding: [0, 1])
        ]
        let original = assemble(.init(words: words, intervals: intervals))
        let repaired = try RecordingTranscriptAssembler.reassignSpeakers(.init(
            transcript: original, diarizedIntervals: intervals
        ))
        XCTAssertEqual(repaired.speakerCount, 2)
        XCTAssertNotEqual(repaired.words?[0].speakerID, repaired.words?[1].speakerID)
        XCTAssertEqual(repaired.words?.map(\.source), [.microphone, .systemAudio])
    }

    func testShortMicrophoneFragmentJoinsItsVoiceWithoutMergingDistinctGuest() {
        let labels = RecordingTranscriptAssembler.voiceClusterLabels([
            .init(speakerID: "mic-main", startTime: 0, endTime: 5, embedding: [1, 0, 0]),
            .init(speakerID: "mic-fragment", startTime: 10, endTime: 14, embedding: [0.77, 0.64, 0]),
            .init(speakerID: "sys-guest", startTime: 15, endTime: 40, embedding: [0, 0, 1])
        ])
        XCTAssertEqual(labels["mic-main"], labels["mic-fragment"])
        XCTAssertNotEqual(labels["mic-main"], labels["sys-guest"])
    }

    func testShortDistinctLocalSpeakerIsRetained() {
        let labels = RecordingTranscriptAssembler.voiceClusterLabels([
            .init(speakerID: "mic-main", startTime: 0, endTime: 30, embedding: [1, 0, 0]),
            .init(speakerID: "mic-guest", startTime: 35, endTime: 37, embedding: [0, 1, 0]),
            .init(speakerID: "sys-guest", startTime: 40, endTime: 60, embedding: [0, 0, 1])
        ])
        XCTAssertEqual(Set(labels.values).count, 3)
    }

    func testSimilarRemoteVoiceIsNotMergedWithLocalVoiceWithoutEchoEvidence() {
        let labels = RecordingTranscriptAssembler.voiceClusterLabels(.init(intervals: [
            .init(speakerID: "mic-main", startTime: 0, endTime: 20, embedding: [1, 0, 0]),
            .init(speakerID: "sys-first", startTime: 0, endTime: 25, embedding: [0, 0, 1]),
            .init(speakerID: "sys-second", startTime: 10, endTime: 16, embedding: [0.95, 0.31, 0])
        ], words: []))
        XCTAssertEqual(Set(labels.values).count, 3)
    }

    func testExplicitSpeakerCountKeepsSimilarDetectedVoicesSeparate() {
        let labels = RecordingTranscriptAssembler.voiceClusterLabels(.init(intervals: [
            .init(speakerID: "mic-first", startTime: 0, endTime: 12, embedding: [1, 0, 0]),
            .init(speakerID: "mic-second", startTime: 15, endTime: 27, embedding: [0.97, 0.2, 0])
        ], words: [], preservesDetectedSpeakers: true))
        XCTAssertEqual(Set(labels.values).count, 2)
    }

    func testRecognitionContextDoesNotJoinDifferentSpeakersOnOneMicrophone() {
        let track = CallAudioAnalysis.Track(source: .microphone, samples: Array(repeating: 0, count: 640_000),
                                            windows: [.init(startTime: 1, endTime: 27)])
        let windows = CallAudioAnalysis.decodingWindows(.init(track: track, intervals: [
            .init(speakerID: "mic-first", startTime: 2, endTime: 13, embedding: [1, 0]),
            .init(speakerID: "mic-second", startTime: 15, endTime: 26, embedding: [0, 1])
        ]))
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].endTime, 13.1, accuracy: 0.001)
        XCTAssertEqual(windows[1].startTime, 14.6, accuracy: 0.001)
        XCTAssertEqual(windows[1].endTime, 26.1, accuracy: 0.001)
    }

    func testSpeakerChangesInsideContinuousMicrophoneSpeechAreMarkedForReview() {
        let transcript = RecordingTranscriptAssembler.assemble(.init(
            mediaPath: "/tmp/call.wav", generatedAt: Date(), duration: 10, confidence: 0.9,
            text: "", suggestedTitle: nil, words: [
                .init(text: "Bonjour", startTime: 1, endTime: 1.8, confidence: 0.9, source: .microphone),
                .init(text: "notre", startTime: 2, endTime: 2.5, confidence: 0.9, source: .microphone),
                .init(text: "équipe", startTime: 3, endTime: 3.5, confidence: 0.9, source: .microphone)
            ], diarizedIntervals: [
                .init(speakerID: "mic-a", startTime: 1, endTime: 1.8, embedding: [1, 0]),
                .init(speakerID: "mic-b", startTime: 2, endTime: 2.5, embedding: [0, 1]),
                .init(speakerID: "mic-a", startTime: 3, endTime: 3.5, embedding: [1, 0])
            ], preservesDetectedSpeakers: true
        ))
        let issues = TranscriptionQuality.speakerIssues(.init(
            transcript: transcript, expectedCount: 2,
            speechBySource: [.microphone: [.init(startTime: 0.8, endTime: 3.7)]]
        ))
        XCTAssertEqual(issues.map(\.kind), [.unstableSpeaker])
    }

    func testAcousticLeakEvidenceSurvivesRemovalOfRepeatedWords() {
        let microphone = CallAudioAnalysis.Track(source: .microphone,
                                                 samples: Array(repeating: 0.01, count: 96_000), windows: [])
        let system = CallAudioAnalysis.Track(source: .systemAudio,
                                             samples: Array(repeating: 0.2, count: 96_000), windows: [])
        let intervals: [DiarizedInterval] = [
            .init(speakerID: "mic-echo", startTime: 0, endTime: 4, embedding: [0.8, 0.6, 0]),
            .init(speakerID: "mic-local", startTime: 0, endTime: 5, embedding: [0, 0, 1]),
            .init(speakerID: "sys-remote", startTime: 0, endTime: 6, embedding: [1, 0, 0])
        ]
        let links = CallAudioAnalysis.voiceLinks(.init(tracks: [microphone, system], intervals: intervals))
        XCTAssertEqual(links, ["mic-echo": "sys-remote"])
        let labels = RecordingTranscriptAssembler.voiceClusterLabels(.init(
            intervals: intervals, words: [], sourceVoiceLinks: links
        ))
        XCTAssertEqual(labels["mic-echo"], labels["sys-remote"])
        XCTAssertNotEqual(labels["mic-local"], labels["sys-remote"])
    }

    func testTwoSpeakersConstrainsCallTopology() {
        let mic = CallAudioAnalysis.Track(source: .microphone, samples: [], windows: [.init(startTime: 0, endTime: 5)])
        let silent = CallAudioAnalysis.Track(source: .systemAudio, samples: [], windows: [])
        let remote = CallAudioAnalysis.Track(source: .systemAudio, samples: [], windows: [.init(startTime: 6, endTime: 10)])
        XCTAssertEqual(CallAudioAnalysis.speakerLimit(.init(count: .two, tracks: [mic, silent], source: .microphone)), 2)
        XCTAssertEqual(CallAudioAnalysis.speakerLimit(.init(count: .two, tracks: [mic, remote], source: .microphone)), 1)
        XCTAssertEqual(CallAudioAnalysis.speakerLimit(.init(count: .two, tracks: [mic, remote], source: .systemAudio)), 1)
        XCTAssertNil(CallAudioAnalysis.speakerLimit(.init(count: .automatic, tracks: [mic, remote], source: .systemAudio)))
    }

    func testReviewEvidenceAndSourceSurviveArtifactRoundTripAndSpeakerMerge() throws {
        var transcript = assemble(.init(words: [
            .init(text: "Local", startTime: 1, endTime: 2, confidence: 0.9, source: .microphone),
            .init(text: "Remote", startTime: 6, endTime: 7, confidence: 0.9, source: .systemAudio)
        ], intervals: [
            .init(speakerID: "mic-a", startTime: 0, endTime: 3, embedding: [1, 0]),
            .init(speakerID: "sys-b", startTime: 5, endTime: 8, embedding: [0, 1])
        ]))
        transcript.quality = .init(pipelineVersion: 2, model: "whisperLarge", languages: ["fr"],
                                   issues: [.init(kind: .missingSpeech, startTime: 10, endTime: 12)])
        let restored = try JSONDecoder().decode(RecordingTranscript.self, from: JSONEncoder().encode(transcript))
        let merged = restored.mergingSpeaker(.init(sourceSpeakerID: "Speaker 2", targetSpeakerID: "Speaker 1"))
        XCTAssertEqual(merged.words?.map(\.speakerID), ["Speaker 1", "Speaker 1"])
        XCTAssertEqual(merged.words?.map(\.source), [.microphone, .systemAudio])
        XCTAssertEqual(merged.quality, transcript.quality)
        XCTAssertTrue(merged.quality?.needsReview == true)
        XCTAssertTrue(merged.formattedText.contains("[00:10] Speech was not transcribed"))
        XCTAssertTrue(merged.markdownText.contains("## Review"))
    }

    private struct AssemblyRequest {
        let words: [TranscriptWord]
        let intervals: [DiarizedInterval]
    }

    private func assemble(_ request: AssemblyRequest) -> RecordingTranscript {
        RecordingTranscriptAssembler.assemble(.init(
            mediaPath: "/tmp/call.wav", generatedAt: Date(), duration: 40, confidence: 0.9,
            text: "", suggestedTitle: nil, words: request.words, wordSources: request.words.map { $0.source ?? .mixed },
            diarizedIntervals: request.intervals
        ))
    }
}

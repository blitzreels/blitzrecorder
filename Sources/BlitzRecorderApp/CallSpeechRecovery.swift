import Foundation

enum CallSpeechRecovery {
    struct Request {
        let tracks: [PreparedTranscriptionTrack]
        let words: [TranscriptWord]
        let sources: [RecordingTranscriptAssembler.WordSource]
        let intervals: [DiarizedInterval]
    }

    struct Result {
        let sources: [RecordingTranscriptAssembler.WordSource]
        let intervals: [DiarizedInterval]
    }

    static func recover(_ request: Request) throws -> Result {
        var result = Result(sources: request.sources, intervals: request.intervals)
        guard request.sources.count == request.words.count,
              let microphone = request.tracks.first(where: { $0.source == .microphone }),
              let system = request.tracks.first(where: { $0.source == .systemAudio }) else { return result }
        let labels = RecordingTranscriptAssembler.voiceClusterLabels(.init(
            intervals: request.intervals, words: Array(zip(request.words, request.sources))
        ))
        let systemIntervals = request.intervals.filter {
            $0.speakerID.hasPrefix(RecordingTranscriptAssembler.systemSpeakerPrefix)
        }
        let identities = Set(systemIntervals.map { labels[$0.speakerID] ?? $0.speakerID })
        guard identities.count == 1, identities.first?.hasPrefix(RecordingTranscriptAssembler.systemSpeakerPrefix) == true
        else { return result }
        let microphoneIntervals = request.intervals.filter {
            RecordingTranscriptAssembler.isMicrophoneSpeaker($0.speakerID)
        }
        let microphoneSamples = try CallAudioAnalysis.readSamples(microphone.audioURL)
        let systemSamples = try CallAudioAnalysis.readSamples(system.audioURL)
        let systemWords = zip(request.words, request.sources).compactMap { word, source in
            source == .systemAudio ? word : nil
        }
        var sources = request.sources
        var intervals = request.intervals
        for index in request.words.indices where sources[index] == .microphone {
            try Task.checkCancellation()
            let word = request.words[index]
            guard word.startTime.isFinite, word.endTime.isFinite, word.endTime > word.startTime,
                  RecordingTranscriptAssembler.speakerID(word: word, intervals: microphoneIntervals) == "undiarized",
                  !systemWords.contains(where: { $0.startTime < word.endTime && $0.endTime > word.startTime }),
                  let nearby = systemIntervals.min(by: {
                      distance(.init(word: word, interval: $0)) < distance(.init(word: word, interval: $1))
                  }), distance(.init(word: word, interval: nearby)) <= 5 else { continue }
            let callPower = power(.init(samples: systemSamples, word: word))
            let microphonePower = power(.init(samples: microphoneSamples, word: word))
            guard callPower >= 0.000064, callPower >= microphonePower * 16 else { continue }
            sources[index] = .systemAudio
            intervals.append(.init(speakerID: nearby.speakerID, startTime: word.startTime,
                                   endTime: word.endTime, embedding: []))
        }
        result = Result(sources: sources, intervals: intervals)
        return result
    }

    private struct DistanceRequest {
        let word: TranscriptWord
        let interval: DiarizedInterval
    }

    private static func distance(_ request: DistanceRequest) -> TimeInterval {
        max(0, request.interval.startTime - request.word.endTime, request.word.startTime - request.interval.endTime)
    }

    private struct PowerRequest {
        let samples: [Float]
        let word: TranscriptWord
    }

    private static func power(_ request: PowerRequest) -> Double {
        let start = Int(min(Double(request.samples.count), max(0, (request.word.startTime - 0.25) * 16_000)))
        let end = Int(min(Double(request.samples.count), max(0, (request.word.endTime + 0.25) * 16_000)))
        guard end > start else { return 0 }
        return request.samples[start..<end].reduce(0.0) { $0 + Double($1) * Double($1) } / Double(end - start)
    }
}

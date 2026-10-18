import AVFoundation
import FluidAudio
import Foundation

enum CallAudioAnalysis {
    struct Request {
        let tracks: [PreparedTranscriptionTrack]
        let intervals: [DiarizedInterval]
        let detector: VadManager
    }

    struct Track: Sendable {
        let source: RecordingTranscriptAssembler.WordSource
        let samples: [Float]
        let windows: [RecordingTranscript.SpeechRange]

        func audio(_ range: RecordingTranscript.SpeechRange) -> [Float] {
            let start = max(0, min(samples.count, Int(range.startTime * 16_000)))
            let end = max(start, min(samples.count, Int(range.endTime * 16_000)))
            return Array(samples[start..<end])
        }

        var languageSample: [Float] {
            var result: [Float] = []
            for range in windows.sorted(by: { $0.endTime - $0.startTime > $1.endTime - $1.startTime }) {
                result.append(contentsOf: audio(range).prefix(max(0, 400_000 - result.count)))
                if result.count >= 400_000 { break }
            }
            return result
        }

        var decodingWindows: [RecordingTranscript.SpeechRange] {
            var result: [RecordingTranscript.SpeechRange] = []
            let duration = Double(samples.count) / 16_000
            for range in windows {
                let padded = RecordingTranscript.SpeechRange(startTime: max(0, range.startTime - 0.4),
                                                              endTime: min(duration, range.endTime + 0.4))
                if let previous = result.last, padded.startTime - previous.endTime <= 1.5,
                   padded.endTime - previous.startTime <= 27 {
                    result[result.count - 1] = .init(startTime: previous.startTime, endTime: padded.endTime)
                } else {
                    result.append(padded)
                }
            }
            return result
        }
    }

    static func analyze(_ request: Request) async throws -> [Track] {
        var tracks: [Track] = []
        for track in request.tracks {
            try Task.checkCancellation()
            let samples = try readSamples(track.audioURL)
            let speech = try await request.detector.segmentSpeech(samples, config: .init(
                minSpeechDuration: 0.2, minSilenceDuration: 0.4, maxSpeechDuration: 20, speechPadding: 0.1
            ))
            tracks.append(Track(source: track.source, samples: samples,
                                windows: speech.map { .init(startTime: $0.startTime, endTime: $0.endTime) }))
        }
        return removingLeakage(.init(tracks: tracks, intervals: request.intervals))
    }

    struct LeakageRequest {
        let tracks: [Track]
        let intervals: [DiarizedInterval]
    }

    struct DecodingRequest {
        let track: Track
        let intervals: [DiarizedInterval]
    }

    static func nativeIntervals(_ request: DecodingRequest) -> [DiarizedInterval] {
        request.intervals.filter { interval in
            switch request.track.source {
            case .microphone: RecordingTranscriptAssembler.isMicrophoneSpeaker(interval.speakerID)
            case .systemAudio: interval.speakerID.hasPrefix(RecordingTranscriptAssembler.systemSpeakerPrefix)
            case .mixed: true
            }
        }.sorted { $0.startTime < $1.startTime }
    }

    static func decodingWindows(_ request: DecodingRequest) -> [RecordingTranscript.SpeechRange] {
        let native = nativeIntervals(request)
        return request.track.decodingWindows.flatMap { window -> [RecordingTranscript.SpeechRange] in
            let relevant = native.filter { $0.startTime < window.endTime && $0.endTime > window.startTime }
            guard Set(relevant.map(\.speakerID)).count > 1 else { return [window] }
            let hasOverlap = relevant.indices.contains { index in
                relevant.dropFirst(index + 1).contains {
                    $0.speakerID != relevant[index].speakerID && $0.startTime < relevant[index].endTime
                }
            }
            guard !hasOverlap else { return [window] }
            var turns: [(id: String, start: Double, end: Double)] = []
            for interval in relevant {
                if let previous = turns.last, previous.id == interval.speakerID {
                    turns[turns.count - 1].end = max(previous.end, interval.endTime)
                } else {
                    turns.append((interval.speakerID, interval.startTime, interval.endTime))
                }
            }
            return turns.compactMap { turn in
                let start = max(window.startTime, turn.start - 0.4)
                let end = min(window.endTime, turn.end + 0.1)
                guard end - start >= 0.15 else { return nil }
                return .init(startTime: start, endTime: end)
            }
        }
    }

    static func voiceLinks(_ request: LeakageRequest) -> [String: String] {
        guard let microphone = request.tracks.first(where: { $0.source == .microphone }),
              let system = request.tracks.first(where: { $0.source == .systemAudio }) else { return [:] }
        let mic = request.intervals.filter { RecordingTranscriptAssembler.isMicrophoneSpeaker($0.speakerID) }
        let remote = request.intervals.filter { $0.speakerID.hasPrefix(RecordingTranscriptAssembler.systemSpeakerPrefix) }
        var result: [String: String] = [:]
        for (id, intervals) in Dictionary(grouping: mic, by: \.speakerID) {
            let duration = intervals.reduce(0.0) { $0 + max(0, $1.endTime - $1.startTime) }
            guard duration >= 3 else { continue }
            var evidence: [String: Double] = [:]
            for interval in intervals {
                let range = RecordingTranscript.SpeechRange(startTime: interval.startTime, endTime: interval.endTime)
                let callPower = power(.init(samples: system.samples, range: range))
                let micPower = power(.init(samples: microphone.samples, range: range))
                guard callPower >= 0.000064, callPower >= micPower * 16,
                      let match = remote.filter({
                          overlap(.init(left: interval, right: $0)) > min(interval.endTime - interval.startTime,
                                                                          $0.endTime - $0.startTime) * 0.6
                      }).min(by: {
                          RecordingTranscriptAssembler.cosineDistance(interval.embedding, $0.embedding)
                              < RecordingTranscriptAssembler.cosineDistance(interval.embedding, $1.embedding)
                      }), RecordingTranscriptAssembler.cosineDistance(interval.embedding, match.embedding) <= 0.35 else { continue }
                evidence[match.speakerID, default: 0] += interval.endTime - interval.startTime
            }
            if let best = evidence.max(by: { $0.value < $1.value }), best.value >= duration * 0.6 {
                result[id] = best.key
            }
        }
        return result
    }

    static func removingLeakage(_ request: LeakageRequest) -> [Track] {
        let tracks = request.tracks
        guard let microphone = tracks.first(where: { $0.source == .microphone }),
              let system = tracks.first(where: { $0.source == .systemAudio }) else { return tracks }
        let micIntervals = request.intervals.filter { RecordingTranscriptAssembler.isMicrophoneSpeaker($0.speakerID) }
        let systemIntervals = request.intervals.filter {
            $0.speakerID.hasPrefix(RecordingTranscriptAssembler.systemSpeakerPrefix)
        }
        let echoIDs = Set(micIntervals.filter { mic in
            let micVoice = mic.embedding
            return systemIntervals.contains { call in
                RecordingTranscriptAssembler.cosineDistance(micVoice, call.embedding) <= 0.35
                    && overlap(.init(left: mic, right: call)) > min(mic.endTime - mic.startTime,
                                                                    call.endTime - call.startTime) * 0.6
            }
        }.map(\.speakerID))
        let nativeIntervals = micIntervals.filter { !echoIDs.contains($0.speakerID) }
        var kept: [RecordingTranscript.SpeechRange] = []
        for range in microphone.windows {
            var cursor = range.startTime
            var start: Double?
            while cursor < range.endTime {
                let end = min(range.endTime, cursor + 0.25)
                let window = RecordingTranscript.SpeechRange(startTime: cursor, endTime: end)
                let native = nativeIntervals.contains { $0.startTime < end && $0.endTime > cursor }
                let callSpeech = system.windows.contains { $0.startTime < end && $0.endTime > cursor }
                let callPower = power(.init(samples: system.samples, range: window))
                let micPower = power(.init(samples: microphone.samples, range: window))
                let leak = !native && callSpeech && callPower >= 0.000064 && callPower >= micPower * 16
                if leak {
                    if let start { kept.append(.init(startTime: start, endTime: cursor)) }
                    start = nil
                } else if start == nil {
                    start = cursor
                }
                cursor = end
            }
            if let start { kept.append(.init(startTime: start, endTime: range.endTime)) }
        }
        return tracks.map { track in
            track.source == .microphone
                ? Track(source: track.source, samples: track.samples, windows: kept.filter { $0.endTime - $0.startTime >= 0.15 })
                : track
        }
    }

    struct SpeakerLimitRequest {
        let count: TranscriptionSpeakerCount
        let tracks: [Track]
        let source: TranscriptWord.Source
    }

    static func speakerLimit(_ request: SpeakerLimitRequest) -> Int? {
        guard request.count == .two else { return nil }
        let sources = Set(request.tracks.filter { !$0.windows.isEmpty }.map(\.source))
        return request.source != .mixed && sources.contains(.microphone) && sources.contains(.systemAudio) ? 1 : 2
    }

    private struct OverlapRequest {
        let left: DiarizedInterval
        let right: DiarizedInterval
    }

    private static func overlap(_ request: OverlapRequest) -> Double {
        max(0, min(request.left.endTime, request.right.endTime) - max(request.left.startTime, request.right.startTime))
    }

    struct PowerRequest {
        let samples: [Float]
        let range: RecordingTranscript.SpeechRange
    }

    static func power(_ request: PowerRequest) -> Double {
        let start = max(0, min(request.samples.count, Int(request.range.startTime * 16_000)))
        let end = max(start, min(request.samples.count, Int(request.range.endTime * 16_000)))
        guard end > start else { return 0 }
        return request.samples[start..<end].reduce(0.0) { $0 + Double($1) * Double($1) } / Double(end - start)
    }

    static func readSamples(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard file.processingFormat.sampleRate == 16_000, file.processingFormat.channelCount == 1,
              file.length > 0, file.length <= Int64(UInt32.max),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)) else {
            throw RecorderError.speechUnavailable
        }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else { throw RecorderError.speechUnavailable }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }
}

import Foundation

extension RecordingTranscriptAssembler {
    struct SpeakerReassignmentRequest {
        let transcript: RecordingTranscript
        let diarizedIntervals: [DiarizedInterval]
    }

    enum SpeakerReassignmentError: LocalizedError, Equatable {
        case missingWordTimings

        var errorDescription: String? {
            switch self {
            case .missingWordTimings:
                return "This transcript has no word timings. Retranscribe it instead."
            }
        }
    }

    static func reassignSpeakers(
        _ request: SpeakerReassignmentRequest
    ) throws -> RecordingTranscript {
        let words = (request.transcript.words ?? []).enumerated().sorted { left, right in
            if left.element.startTime == right.element.startTime {
                return left.offset < right.offset
            }
            return left.element.startTime < right.element.startTime
        }.map(\.element)
        guard !words.isEmpty else { throw SpeakerReassignmentError.missingWordTimings }
        let sources = inferredWordSources(.init(words: words, intervals: request.diarizedIntervals))
        let labels = voiceClusterLabels(request.diarizedIntervals)
        let trackIntervals = TrackIntervals(.init(intervals: request.diarizedIntervals, labels: labels))
        let reassigned = voiceGroupedTranscript(VoiceGroupingRequest(
            metadata: .init(request.transcript),
            words: Array(zip(words, sources)),
            intervals: request.diarizedIntervals,
            trackIntervals: trackIntervals
        ))
        return carryingSpeakerNames(.init(
            reassigned: reassigned,
            previousSpeakerIDs: words.map(\.speakerID),
            previous: request.transcript
        ))
    }

    static let speakerFixMergeCosineDistance: Float = 0.2
    static let speakerFixAttachCosineDistance: Float = 0.5
    static let speakerFixMinorClusterShare = 0.15

    private struct VoiceCluster {
        var members: [String: Double]
        var sum: [Float]
        var duration: Double

        var label: String {
            members.max { left, right in
                left.value == right.value ? left.key > right.key : left.value < right.value
            }?.key ?? ""
        }

        mutating func absorb(_ other: VoiceCluster) {
            members.merge(other.members, uniquingKeysWith: +)
            for index in sum.indices { sum[index] += other.sum[index] }
            duration += other.duration
        }
    }

    static func voiceClusterLabels(_ intervals: [DiarizedInterval]) -> [String: String] {
        var clusters: [VoiceCluster] = []
        var byID: [String: Int] = [:]
        for interval in intervals where !interval.embedding.isEmpty {
            let weight = max(interval.endTime - interval.startTime, 0.001)
            let weighted = interval.embedding.map { $0 * Float(weight) }
            if let index = byID[interval.speakerID] {
                guard clusters[index].sum.count == weighted.count else { continue }
                clusters[index].absorb(.init(members: [interval.speakerID: weight], sum: weighted, duration: weight))
            } else {
                byID[interval.speakerID] = clusters.count
                clusters.append(.init(members: [interval.speakerID: weight], sum: weighted, duration: weight))
            }
        }
        mergeClosestClusters(&clusters)
        attachMinorClusters(&clusters)
        var labels: [String: String] = [:]
        for cluster in clusters {
            for member in cluster.members.keys { labels[member] = cluster.label }
        }
        return labels
    }

    private static func mergeClosestClusters(_ clusters: inout [VoiceCluster]) {
        while clusters.count > 1 {
            var best: (left: Int, right: Int, distance: Float)?
            for left in clusters.indices {
                for right in clusters.indices where right > left {
                    let distance = cosineDistance(clusters[left].sum, clusters[right].sum)
                    if distance < (best?.distance ?? .infinity) { best = (left, right, distance) }
                }
            }
            guard let best, best.distance <= speakerFixMergeCosineDistance else { return }
            clusters[best.left].absorb(clusters[best.right])
            clusters.remove(at: best.right)
        }
    }

    private static func attachMinorClusters(_ clusters: inout [VoiceCluster]) {
        let largest = clusters.map(\.duration).max() ?? 0
        let isMinor = { (cluster: VoiceCluster) in cluster.duration < largest * speakerFixMinorClusterShare }
        let minors = clusters.filter(isMinor).sorted { $0.duration < $1.duration }
        var majors = clusters.filter { !isMinor($0) }
        var remaining: [VoiceCluster] = []
        for minor in minors {
            let nearest = majors.indices.min {
                cosineDistance(minor.sum, majors[$0].sum) < cosineDistance(minor.sum, majors[$1].sum)
            }
            if let nearest, cosineDistance(minor.sum, majors[nearest].sum) <= speakerFixAttachCosineDistance {
                majors[nearest].absorb(minor)
            } else {
                remaining.append(minor)
            }
        }
        clusters = majors + remaining
    }

    static func cosineDistance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return .infinity }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for k in a.indices {
            dot += a[k] * b[k]
            normA += a[k] * a[k]
            normB += b[k] * b[k]
        }
        guard normA > 0, normB > 0 else { return .infinity }
        return 1 - dot / (normA.squareRoot() * normB.squareRoot())
    }

    struct TrackIntervals {
        struct BuildRequest {
            let intervals: [DiarizedInterval]
            let labels: [String: String]
        }

        struct WordRequest {
            let word: TranscriptWord
            let source: WordSource
        }

        let microphone: [DiarizedInterval]
        let system: [DiarizedInterval]
        let all: [DiarizedInterval]

        init(_ request: BuildRequest) {
            func labeled(_ interval: DiarizedInterval) -> DiarizedInterval {
                DiarizedInterval(
                    speakerID: request.labels[interval.speakerID] ?? interval.speakerID,
                    startTime: interval.startTime,
                    endTime: interval.endTime,
                    embedding: interval.embedding
                )
            }
            microphone = request.intervals.filter { isMicrophoneSpeaker($0.speakerID) }.map(labeled)
            system = request.intervals.filter { $0.speakerID.hasPrefix(systemSpeakerPrefix) }.map(labeled)
            all = request.intervals.map(labeled)
        }

        func speakerID(_ request: WordRequest) -> String {
            let intervals: [DiarizedInterval]
            switch request.source {
            case .microphone: intervals = microphone
            case .systemAudio: intervals = system
            case .mixed: intervals = all
            }
            let resolved = RecordingTranscriptAssembler.speakerID(word: request.word, intervals: intervals)
            guard resolved == "undiarized" else { return resolved }
            let nearest = intervals.min { left, right in
                distance(from: request.word, to: left) < distance(from: request.word, to: right)
            }
            return nearest?.speakerID ?? (request.source == .microphone ? microphoneSpeakerID : resolved)
        }

        private func distance(from word: TranscriptWord, to interval: DiarizedInterval) -> TimeInterval {
            max(0, interval.startTime - word.endTime, word.startTime - interval.endTime)
        }
    }

    struct WordSourceInferenceRequest {
        let words: [TranscriptWord]
        let intervals: [DiarizedInterval]
    }

    static func inferredWordSources(
        _ request: WordSourceInferenceRequest
    ) -> [WordSource] {
        let microphoneIntervals = request.intervals.filter { isMicrophoneSpeaker($0.speakerID) }
        let systemIntervals = request.intervals.filter { $0.speakerID.hasPrefix(systemSpeakerPrefix) }
        switch (microphoneIntervals.isEmpty, systemIntervals.isEmpty) {
        case (true, true):
            return Array(repeating: .mixed, count: request.words.count)
        case (false, true):
            return Array(repeating: .microphone, count: request.words.count)
        case (true, false):
            return Array(repeating: .systemAudio, count: request.words.count)
        case (false, false):
            break
        }
        let decided: [WordSource?] = request.words.map { word in
            let microphone = overlap(.init(word: word, intervals: microphoneIntervals))
            let system = overlap(.init(word: word, intervals: systemIntervals))
            if microphone == 0 && system == 0 { return nil }
            return system >= microphone ? .systemAudio : .microphone
        }
        var votes: [String: (microphone: Int, system: Int)] = [:]
        for (word, source) in zip(request.words, decided) {
            guard let source, let speakerID = word.speakerID else { continue }
            var vote = votes[speakerID] ?? (0, 0)
            if source == .systemAudio { vote.system += 1 } else { vote.microphone += 1 }
            votes[speakerID] = vote
        }
        return zip(request.words, decided).map { word, source in
            if let source { return source }
            guard let speakerID = word.speakerID, let vote = votes[speakerID] else { return .microphone }
            return vote.system > vote.microphone ? .systemAudio : .microphone
        }
    }

    private struct OverlapRequest {
        let word: TranscriptWord
        let intervals: [DiarizedInterval]
    }

    private static func overlap(_ request: OverlapRequest) -> TimeInterval {
        request.intervals.reduce(into: 0) { total, interval in
            total += max(0, min(request.word.endTime, interval.endTime)
                - max(request.word.startTime, interval.startTime))
        }
    }

    private struct SpeakerOverlap {
        let newID: String
        let previousID: String
        let count: Int
    }

    private struct NameCarryRequest {
        let reassigned: RecordingTranscript
        let previousSpeakerIDs: [String?]
        let previous: RecordingTranscript
    }

    private static func carryingSpeakerNames(_ request: NameCarryRequest) -> RecordingTranscript {
        let previousNames = Dictionary(
            request.previous.speakers.compactMap { speaker -> (String, String)? in
                let name = speaker.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty ? nil : (speaker.id, name)
            },
            uniquingKeysWith: { first, _ in first }
        )
        guard !previousNames.isEmpty else { return request.reassigned }
        var overlaps: [String: [String: Int]] = [:]
        for (word, previousID) in zip(request.reassigned.words ?? [], request.previousSpeakerIDs) {
            guard let newID = word.speakerID, let previousID, previousNames[previousID] != nil else { continue }
            overlaps[newID, default: [:]][previousID, default: 0] += 1
        }
        var pairs: [SpeakerOverlap] = []
        for (newID, counts) in overlaps {
            for (previousID, count) in counts {
                pairs.append(SpeakerOverlap(newID: newID, previousID: previousID, count: count))
            }
        }
        pairs.sort { left, right in
            if left.count != right.count { return left.count > right.count }
            return left.newID < right.newID
        }
        var names: [String: String] = [:]
        var usedPreviousIDs: Set<String> = []
        for pair in pairs where names[pair.newID] == nil && !usedPreviousIDs.contains(pair.previousID) {
            names[pair.newID] = previousNames[pair.previousID]
            usedPreviousIDs.insert(pair.previousID)
        }
        var transcript = request.reassigned
        transcript.speakers = transcript.speakers.map { speaker in
            guard let name = names[speaker.id] else { return speaker }
            return RecordingTranscript.Speaker(id: speaker.id, name: name, context: speaker.context)
        }
        return transcript
    }
}

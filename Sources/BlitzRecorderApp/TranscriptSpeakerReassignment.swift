import Foundation

extension RecordingTranscriptAssembler {
    struct SpeakerReassignmentRequest {
        let transcript: RecordingTranscript
        let diarizedIntervals: [DiarizedInterval]
        var recoveredSources: [WordSource]? = nil
        var sourceVoiceLinks: [String: String] = [:]
        var preservesDetectedSpeakers = false
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
        let ordered = (request.transcript.words ?? []).enumerated().sorted { left, right in
            if left.element.startTime == right.element.startTime {
                return left.offset < right.offset
            }
            return left.element.startTime < right.element.startTime
        }
        let words = ordered.map(\.element)
        guard !words.isEmpty else { throw SpeakerReassignmentError.missingWordTimings }
        let inferred = inferredWordSources(.init(words: words, intervals: request.diarizedIntervals))
        let sources: [WordSource]
        if let recovered = request.recoveredSources, recovered.count == words.count {
            sources = ordered.map { recovered[$0.offset] }
        } else {
            sources = zip(words, inferred).map { $0.source ?? $1 }
        }
        let labels = voiceClusterLabels(.init(intervals: request.diarizedIntervals, words: Array(zip(words, sources)),
                                              sourceVoiceLinks: request.sourceVoiceLinks,
                                              preservesDetectedSpeakers: request.preservesDetectedSpeakers))
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
    static let speakerFixEchoCosineDistance: Float = 0.35
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
        voiceClusterLabels(.init(intervals: intervals, words: []))
    }

    struct VoiceClusteringRequest {
        let intervals: [DiarizedInterval]
        let words: [(TranscriptWord, WordSource)]
        var sourceVoiceLinks: [String: String] = [:]
        var preservesDetectedSpeakers = false
    }

    static func voiceClusterLabels(_ request: VoiceClusteringRequest) -> [String: String] {
        let intervals = request.intervals
        var clusters: [VoiceCluster] = []
        var byID: [String: Int] = [:]
        for interval in intervals where !interval.embedding.isEmpty && interval.embedding.allSatisfy(\.isFinite) {
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
        if !request.preservesDetectedSpeakers {
            clusters = mergingClosestClusters(.init(clusters: clusters, evidence: request))
            clusters = attachingMinorClusters(.init(clusters: clusters, evidence: request))
        }
        var labels: [String: String] = [:]
        for cluster in clusters {
            for member in cluster.members.keys { labels[member] = cluster.label }
        }
        for (microphone, system) in request.sourceVoiceLinks {
            labels[microphone] = labels[system] ?? system
        }
        return labels
    }

    private struct ClusterMergeRequest {
        let clusters: [VoiceCluster]
        let evidence: VoiceClusteringRequest
    }

    private static func mergingClosestClusters(_ request: ClusterMergeRequest) -> [VoiceCluster] {
        var clusters = request.clusters
        while clusters.count > 1 {
            var best: (left: Int, right: Int, distance: Float)?
            for left in clusters.indices {
                for right in clusters.indices where right > left {
                    let distance = cosineDistance(clusters[left].sum, clusters[right].sum)
                    let crossTrack = isMicrophoneSpeaker(clusters[left].label) != isMicrophoneSpeaker(clusters[right].label)
                        && (clusters[left].label.hasPrefix(systemSpeakerPrefix) || clusters[right].label.hasPrefix(systemSpeakerPrefix))
                    guard !crossTrack && distance <= speakerFixMergeCosineDistance
                        || crossTrack && distance <= speakerFixEchoCosineDistance && matchesCrossTrackEcho(.init(
                            left: clusters[left], right: clusters[right], evidence: request.evidence
                        )) else { continue }
                    if distance < (best?.distance ?? .infinity) { best = (left, right, distance) }
                }
            }
            guard let best else { return clusters }
            clusters[best.left].absorb(clusters[best.right])
            clusters.remove(at: best.right)
        }
        return clusters
    }

    private struct EchoClusterRequest {
        let left: VoiceCluster
        let right: VoiceCluster
        let evidence: VoiceClusteringRequest
    }

    private static func matchesCrossTrackEcho(_ request: EchoClusterRequest) -> Bool {
        let leftIsMicrophone = isMicrophoneSpeaker(request.left.label)
        let rightIsMicrophone = isMicrophoneSpeaker(request.right.label)
        guard leftIsMicrophone != rightIsMicrophone else { return false }
        let microphone = leftIsMicrophone ? request.left : request.right
        let system = leftIsMicrophone ? request.right : request.left
        guard system.label.hasPrefix(systemSpeakerPrefix) else { return false }
        let microphoneIntervals = request.evidence.intervals.filter { microphone.members[$0.speakerID] != nil }
        let systemIntervals = request.evidence.intervals.filter { system.members[$0.speakerID] != nil }
        let microphoneWords = request.evidence.words.compactMap { word, source -> TranscriptWord? in
            guard source == .microphone,
                  microphoneIntervals.contains(where: {
                      $0.startTime < word.endTime && $0.endTime > word.startTime
                  }) else { return nil }
            return word
        }
        let systemWords = request.evidence.words.compactMap { word, source -> TranscriptWord? in
            guard source == .systemAudio,
                  systemIntervals.contains(where: {
                      $0.startTime < word.endTime && $0.endTime > word.startTime
                  }) else { return nil }
            return word
        }
        guard microphoneWords.count >= 6 else { return false }
        let matching = microphoneWords.filter { matchesWords(.init(word: $0, candidates: systemWords)) }.count
        return Double(matching) / Double(microphoneWords.count) >= 0.6
    }

    private struct MinorClusterRequest {
        let clusters: [VoiceCluster]
        let evidence: VoiceClusteringRequest
    }

    private static func attachingMinorClusters(_ request: MinorClusterRequest) -> [VoiceCluster] {
        let clusters = request.clusters
        let isMinor = { (cluster: VoiceCluster) in
            let largest = clusters.filter {
                isMicrophoneSpeaker($0.label) == isMicrophoneSpeaker(cluster.label)
            }.map(\.duration).max() ?? 0
            return cluster.duration < largest * speakerFixMinorClusterShare
                || cluster.duration <= 8 && cluster.duration < largest * 0.9
        }
        let minors = clusters.filter(isMinor).sorted { $0.duration < $1.duration }
        var majors = clusters.filter { !isMinor($0) }
        var remaining: [VoiceCluster] = []
        for minor in minors {
            let nearest = majors.indices.min {
                cosineDistance(minor.sum, majors[$0].sum) < cosineDistance(minor.sum, majors[$1].sum)
            }
            let isCrossTrack = nearest.map { index in
                isMicrophoneSpeaker(minor.label) != isMicrophoneSpeaker(majors[index].label)
            } ?? false
            let overlapsOtherTrack = nearest.map { index in
                let minorIntervals = request.evidence.intervals.filter { minor.members[$0.speakerID] != nil }
                let majorIntervals = request.evidence.intervals.filter { majors[index].members[$0.speakerID] != nil }
                let overlap = minorIntervals.reduce(0.0) { total, interval in
                    total + majorIntervals.reduce(0.0) { subtotal, major in
                        subtotal + max(0, min(interval.endTime, major.endTime) - max(interval.startTime, major.startTime))
                    }
                }
                return overlap >= minor.duration * 0.5
            } ?? false
            let threshold = isCrossTrack && overlapsOtherTrack
                ? speakerFixAttachCosineDistance : speakerFixMergeCosineDistance
            let nearestDistance = nearest.map { cosineDistance(minor.sum, majors[$0].sum) } ?? .infinity
            let nextDistance = majors.indices.filter { $0 != nearest }.map {
                cosineDistance(minor.sum, majors[$0].sum)
            }.min() ?? .infinity
            let isShortMicrophoneFragment = !isCrossTrack && isMicrophoneSpeaker(minor.label)
                && (minor.duration <= 3 && nearestDistance <= 0.4
                    || minor.duration <= 8 && nearestDistance <= 0.3)
                && nextDistance - nearestDistance >= 0.15
            let corroborated = nearest.map {
                !isCrossTrack || matchesCrossTrackEcho(.init(left: minor, right: majors[$0], evidence: request.evidence))
            } ?? false
            if let nearest, corroborated && (nearestDistance <= threshold || isShortMicrophoneFragment) {
                majors[nearest].absorb(minor)
            } else {
                remaining.append(minor)
            }
        }
        return majors + remaining
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
            let nativeIDs = Set(intervals.map(\.speakerID).filter { speakerID in
                switch request.source {
                case .microphone: RecordingTranscriptAssembler.isMicrophoneSpeaker(speakerID)
                case .systemAudio: speakerID.hasPrefix(RecordingTranscriptAssembler.systemSpeakerPrefix)
                case .mixed: false
                }
            })
            if nativeIDs.count == 1 { return nativeIDs.first! }
            return "undiarized"
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
        var previousIDs: [String: String] = [:]
        var usedPreviousIDs: Set<String> = []
        for pair in pairs where names[pair.newID] == nil && !usedPreviousIDs.contains(pair.previousID) {
            names[pair.newID] = previousNames[pair.previousID]
            previousIDs[pair.newID] = pair.previousID
            usedPreviousIDs.insert(pair.previousID)
        }
        var transcript = request.reassigned
        transcript.speakers = transcript.speakers.map { speaker in
            guard let name = names[speaker.id] else { return speaker }
            var renamed = speaker
            renamed.name = name
            let previous = request.previous.speakers.first { $0.id == previousIDs[speaker.id] }
            renamed.context = previous?.context ?? speaker.context
            renamed.savedVoiceID = previous?.savedVoiceID
            return renamed
        }
        return transcript
    }
}

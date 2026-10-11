import AVFoundation
import Foundation

struct EditorTrackVolumeChange {
    let source: CaptureSource
    let volume: Double
}

struct EditorAudioLevels: Codable, Equatable, Sendable {
    var microphone: Double = 1
    var systemAudio: Double = 1
    var regions: [EditorAudioVolumeRegion] = []

    static let unity = EditorAudioLevels()

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        microphone = try values.decodeIfPresent(Double.self, forKey: .microphone) ?? 1
        systemAudio = try values.decodeIfPresent(Double.self, forKey: .systemAudio) ?? 1
        regions = try values.decodeIfPresent([EditorAudioVolumeRegion].self, forKey: .regions) ?? []
    }

    func volume(for source: CaptureSource) -> Double {
        switch source {
        case .microphone: return Self.clamped(microphone)
        case .systemAudio: return Self.clamped(systemAudio)
        default: return 1
        }
    }

    mutating func setVolume(_ change: EditorTrackVolumeChange) {
        guard change.volume.isFinite else { return }
        switch change.source {
        case .microphone: microphone = Self.clamped(change.volume)
        case .systemAudio: systemAudio = Self.clamped(change.volume)
        default: break
        }
    }

    func applying(to settings: RecordingSettings) -> RecordingSettings {
        var result = settings
        result.microphoneGain *= volume(for: .microphone)
        result.systemAudioGain *= volume(for: .systemAudio)
        result.audioVolumeRegions = regions
        return result
    }

    mutating func setRegion(_ region: EditorAudioVolumeRegion) {
        guard region.start.isFinite, region.end.isFinite, region.end > region.start, region.volume.isFinite else { return }
        var result: [EditorAudioVolumeRegion] = []
        for existing in regions {
            guard existing.source == region.source, existing.start < region.end, existing.end > region.start else {
                result.append(existing)
                continue
            }
            if existing.start < region.start {
                result.append(.init(source: existing.source, start: existing.start, end: region.start, volume: existing.volume))
            }
            if existing.end > region.end {
                result.append(.init(source: existing.source, start: region.end, end: existing.end, volume: existing.volume))
            }
        }
        if region.volume < 1 {
            result.append(.init(source: region.source, start: region.start, end: region.end, volume: Self.clamped(region.volume)))
        }
        regions = result.sorted { $0.start < $1.start }
    }

    func regionVolume(_ region: EditorAudioVolumeRegion) -> Double {
        regions.first { $0.source == region.source && $0.start <= region.start + 1.0 / 600
            && $0.end >= region.end - 1.0 / 600 }.map { Self.clamped($0.volume) } ?? 1
    }

    private static func clamped(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 1
    }
}

struct EditorAudioVolumeRegion: Codable, Equatable, Sendable {
    let source: CaptureSource
    let start: Double
    let end: Double
    let volume: Double
}

enum EditorAudioVolumeAutomation {
    struct Request {
        let parameters: AVMutableAudioMixInputParameters
        let source: CaptureSource
        let baseVolume: Float
        let regions: [EditorAudioVolumeRegion]
        let timeMap: TimelineTimeMap
    }

    static func apply(_ request: Request) {
        let base = max(0, min(2, request.baseVolume))
        let duration = request.timeMap.outputDuration.seconds
        let regions = request.regions.filter { $0.source == request.source }.compactMap { region -> (start: Double, end: Double, volume: Float)? in
            guard region.start.isFinite, region.end.isFinite, region.end > region.start, region.volume.isFinite else { return nil }
            let start = max(0, request.timeMap.outputSeconds(forTakeSeconds: region.start))
            let end = min(duration, request.timeMap.outputSeconds(forTakeSeconds: region.end))
            guard end > start else { return nil }
            return (start, end, base * Float(min(1, max(0, region.volume))))
        }
        guard !regions.isEmpty else { request.parameters.setVolume(base, at: .zero); return }
        let boundaries = Set([0, duration] + regions.flatMap { [$0.start, $0.end] }).sorted()
        for (start, end) in zip(boundaries, boundaries.dropFirst()) where end > start {
            let midpoint = (start + end) / 2
            let volume = regions.last { $0.start <= midpoint && midpoint < $0.end }?.volume ?? base
            request.parameters.setVolumeRamp(fromStartVolume: volume, toEndVolume: volume,
                timeRange: CMTimeRange(start: TimelineTimeMap.time(start), end: TimelineTimeMap.time(end)))
        }
    }
}

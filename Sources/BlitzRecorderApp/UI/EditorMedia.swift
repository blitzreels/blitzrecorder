import AppKit
import AVFoundation
import Foundation
import Observation
import SwiftUI

enum EditorSelection: Equatable {
    case placed(EditorPlacedItem.ID)
    case segment(Int)
    case asset(String)
    case range(EditorTimeRange)
    case ranges(SilenceSegmentSelection)
    case silenceRange(EditorTimeRange)
    case silenceRanges(SilenceSegmentSelection)

    var timeRange: EditorTimeRange? {
        switch self {
        case .range(let range), .silenceRange(let range): return range
        case .ranges(let selection): return selection.bounds
        case .silenceRanges(let selection): return selection.ranges.count == 1 ? selection.ranges.first : nil
        default: return nil
        }
    }
    var rangeSelection: SilenceSegmentSelection? {
        switch self {
        case .range(let range), .silenceRange(let range): return .init(range)
        case .ranges(let selected), .silenceRanges(let selected): return selected
        default: return nil
        }
    }
    var silenceSelection: SilenceSegmentSelection? {
        switch self {
        case .silenceRange(let range): return SilenceSegmentSelection(range)
        case .silenceRanges(let selection): return selection
        default: return nil
        }
    }
}

struct EditorAsset: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case output
        case screen
        case camera
        case microphone
        case systemAudio
        case other
    }

    let id: String
    let kind: Kind
    let url: URL
    let title: String
    let exists: Bool
    let isVideo: Bool
    let isAudio: Bool

    var isPlayable: Bool { isVideo || isAudio }

    var systemImage: String {
        switch kind {
        case .output: return "film"
        case .screen: return BlitzSymbols.screen
        case .camera: return BlitzSymbols.camera
        case .microphone: return BlitzSymbols.microphone
        case .systemAudio: return BlitzSymbols.systemAudio
        case .other: return "doc"
        }
    }

    var tint: Color {
        switch kind {
        case .output, .screen: return BlitzUI.trackScreen
        case .camera: return BlitzUI.trackCamera
        case .microphone: return BlitzUI.trackMicrophone
        case .systemAudio: return BlitzUI.trackSystemAudio
        case .other: return BlitzUI.secondaryText
        }
    }

    private init(url: URL, kind: Kind, role: String, exists: Bool) {
        self.id = url.path
        self.kind = kind
        self.url = url
        self.title = Self.title(for: kind, role: role)
        self.exists = exists
        let pathExtension = url.pathExtension.lowercased()
        self.isVideo = ["mov", "mp4", "m4v"].contains(pathExtension)
        self.isAudio = ["m4a", "mp3", "wav", "aac", "caf"].contains(pathExtension)
    }

    static func assets(project: RecordingProject, finalVideoURL: URL?) -> [EditorAsset] {
        var assets: [EditorAsset] = []

        let outputURL = finalVideoURL ?? project.finalVideoPath.map { URL(fileURLWithPath: $0) }
        if let outputURL, FileManager.default.fileExists(atPath: outputURL.path) {
            assets.append(EditorAsset(url: outputURL, kind: .output, role: "output", exists: true))
        }

        let settingsSources = Set(project.settings.enabledSources.compactMap(CaptureSource.init(rawValue:)))
        let sceneSources = Set(project.sceneEvents.flatMap { event in
            event.scene.enabledSources.compactMap(CaptureSource.init(rawValue:))
        })
        let enabledSources = settingsSources.union(sceneSources)
        let knownRoles = ["screen", "camera", "microphone", "systemAudio"]
        let known = knownRoles.flatMap { role in
            project.sources.filter { $0.role == role }
        }
        let others = project.sources.filter { !knownRoles.contains($0.role) }
        for source in known + others {
            guard shouldShowSource(source, enabledSources: enabledSources) else { continue }
            assets.append(
                EditorAsset(
                    url: URL(fileURLWithPath: source.path),
                    kind: Kind(rawValue: source.role) ?? .other,
                    role: source.role,
                    exists: source.exists
                )
            )
        }
        return assets
    }

    static func output(url: URL) -> EditorAsset {
        EditorAsset(
            url: url,
            kind: .output,
            role: "output",
            exists: FileManager.default.fileExists(atPath: url.path)
        )
    }

    private static func shouldShowSource(
        _ source: RecordingProject.SourceFile,
        enabledSources: Set<CaptureSource>
    ) -> Bool {
        if source.exists {
            return true
        }
        guard let captureSource = captureSource(forRole: source.role) else {
            return false
        }
        return enabledSources.contains(captureSource)
    }

    private static func captureSource(forRole role: String) -> CaptureSource? {
        switch role {
        case "screen": return .screen
        case "camera": return .camera
        case "microphone": return .microphone
        case "systemAudio": return .systemAudio
        default: return nil
        }
    }

    private static func title(for kind: Kind, role: String) -> String {
        switch kind {
        case .output: return "Output"
        case .screen: return "Screen"
        case .camera: return "Camera"
        case .microphone: return "Mic"
        case .systemAudio: return "Mac audio"
        case .other:
            return role
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }
}

private struct EditorLoadedMedia: Sendable {
    let id: String
    let duration: Double
    let fileSize: String
    let poster: CGImage?
    let waveform: EditorAudioWaveform?
    let technicalMetadata: EditorMediaTechnicalMetadata
}

struct EditorFilmstripLoadRequest: Sendable {
    let assetID: String
    let url: URL
    let frameCount: Int
}

@MainActor
@Observable
final class EditorMediaLibrary {
    private(set) var posters: [String: CGImage] = [:]
    private(set) var filmstrips: [String: [CGImage]] = [:]
    private(set) var waveforms: [String: [Float]] = [:]
    private(set) var timelineWaveforms: [String: EditorAudioWaveform] = [:]
    private(set) var audioActivity: [String: EditorAudioActivity.State] = [:]
    private(set) var durations: [String: Double] = [:]
    private(set) var fileSizes: [String: String] = [:]
    private(set) var technicalMetadata: [String: EditorMediaTechnicalMetadata] = [:]

    private(set) var loadingIDs: Set<String> = []
    private(set) var filmstripLoadingCounts: [String: Int] = [:]

    enum LoadPurpose: Int, Sendable {
        case metadata
        case library
        case editor
    }

    struct AssetLoadRequest {
        let assets: [EditorAsset]
        let purpose: LoadPurpose
    }

    private struct MediaLoadRequest {
        let asset: EditorAsset
        let purpose: LoadPurpose
    }

    @ObservationIgnored private var loadedPurposes: [String: LoadPurpose] = [:]
    @ObservationIgnored private var loadTokens: [String: UUID] = [:]
    @ObservationIgnored private var activityTokens: [String: UUID] = [:]
    @ObservationIgnored private let analyzeAudio: @Sendable (EditorAsset) async throws -> [EditorTimeRange]

    init(analyzeAudio: @escaping @Sendable (EditorAsset) async throws -> [EditorTimeRange] = {
        try await EditorAudioActivity.load($0)
    }) {
        self.analyzeAudio = analyzeAudio
    }

    func retryAudioActivity(_ asset: EditorAsset) async {
        guard !Task.isCancelled, case .failed = audioActivity[asset.id] else { return }
        await analyzeAudioActivity(asset)
    }

    private func analyzeAudioActivity(_ asset: EditorAsset) async {
        guard !Task.isCancelled, asset.kind == .systemAudio else { return }
        let previous: EditorAudioActivity.State?
        if case .loading = audioActivity[asset.id] { previous = nil }
        else { previous = audioActivity[asset.id] }
        let token = UUID()
        activityTokens[asset.id] = token
        audioActivity[asset.id] = .loading
        do {
            let ranges = try await analyzeAudio(asset)
            try Task.checkCancellation()
            guard activityTokens[asset.id] == token else { return }
            audioActivity[asset.id] = .ready(ranges)
        } catch {
            guard activityTokens[asset.id] == token else { return }
            audioActivity[asset.id] = Task.isCancelled || error is CancellationError
                ? previous : .failed(error.localizedDescription)
        }
        activityTokens[asset.id] = nil
    }

    struct WaveformSource {
        let assetID: String
        let url: URL
    }

    /// Redraws an audio track from another file of the same length, such as the cleaned microphone.
    func showWaveform(_ source: WaveformSource) async {
        guard let duration = durations[source.assetID],
              let waveform = await EditorAudioWaveform.load(.init(asset: AVURLAsset(url: source.url), duration: duration)),
              !Task.isCancelled else { return }
        timelineWaveforms[source.assetID] = waveform
        waveforms[source.assetID] = waveform.overview
    }

    func loadAssets(_ assets: [EditorAsset]) async {
        await loadAssets(.init(assets: assets, purpose: .editor))
    }

    func loadAssets(_ request: AssetLoadRequest) async {
        guard !Task.isCancelled else { return }
        let pending = request.assets.filter {
            $0.exists && $0.isPlayable
                && (loadedPurposes[$0.id]?.rawValue ?? -1) < request.purpose.rawValue
        }
        let token = UUID()
        let concurrency = request.purpose == .editor ? 2 : 1
        await withTaskGroup(of: EditorLoadedMedia?.self) { group in
            var nextIndex = 0
            @MainActor func enqueueNext() {
                guard !Task.isCancelled, nextIndex < pending.count else { return }
                let asset = pending[nextIndex]
                nextIndex += 1
                loadingIDs.insert(asset.id)
                loadTokens[asset.id] = token
                group.addTask(priority: .utility) {
                    await Self.load(.init(asset: asset, purpose: request.purpose))
                }
            }
            for _ in 0..<concurrency { enqueueNext() }
            for await loaded in group {
                if let loaded, !Task.isCancelled, loadTokens[loaded.id] == token {
                    durations[loaded.id] = loaded.duration
                    fileSizes[loaded.id] = loaded.fileSize
                    technicalMetadata[loaded.id] = loaded.technicalMetadata
                    loadedPurposes[loaded.id] = request.purpose
                    if let poster = loaded.poster { posters[loaded.id] = poster }
                    if let waveform = loaded.waveform {
                        waveforms[loaded.id] = waveform.overview
                        timelineWaveforms[loaded.id] = waveform
                    }
                }
                enqueueNext()
            }
        }
        for asset in pending where loadTokens[asset.id] == token {
            loadTokens[asset.id] = nil
            loadingIDs.remove(asset.id)
        }
        guard request.purpose == .editor else { return }
        await withTaskGroup(of: Void.self) { group in
            for asset in request.assets where asset.kind == .systemAudio {
                switch audioActivity[asset.id] {
                case .ready, .failed: break
                case .loading, nil: group.addTask { await self.analyzeAudioActivity(asset) }
                }
            }
        }
        for asset in request.assets where asset.exists && asset.isVideo {
            guard !Task.isCancelled else { return }
            await loadFilmstrip(request: .init(assetID: asset.id, url: asset.url, frameCount: 16))
        }
    }

    func loadFilmstrip(request: EditorFilmstripLoadRequest) async {
        guard !Task.isCancelled else { return }
        let loadedCount = filmstrips[request.assetID]?.count ?? 0
        let loadingCount = filmstripLoadingCounts[request.assetID] ?? 0
        guard request.frameCount > max(loadedCount, loadingCount) else { return }

        filmstripLoadingCounts[request.assetID] = request.frameCount
        defer {
            if filmstripLoadingCounts[request.assetID] == request.frameCount {
                filmstripLoadingCounts[request.assetID] = nil
            }
        }

        let frames = await Self.loadFilmstripFrames(request: request)
        guard !Task.isCancelled,
              frames.count > (filmstrips[request.assetID]?.count ?? 0) else {
            return
        }
        filmstrips[request.assetID] = frames
    }

    nonisolated private static func load(_ request: MediaLoadRequest) async -> EditorLoadedMedia? {
        guard !Task.isCancelled else { return nil }
        let asset = request.asset
        let avAsset = AVURLAsset(url: asset.url)
        guard let duration = try? await avAsset.load(.duration) else { return nil }
        let seconds = duration.seconds.isFinite ? max(0, duration.seconds) : 0

        let fileSize: String
        if let attributes = try? FileManager.default.attributesOfItem(atPath: asset.url.path),
           let bytes = (attributes[.size] as? NSNumber)?.int64Value {
            fileSize = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        } else {
            fileSize = ""
        }

        var poster: CGImage?
        var waveform: EditorAudioWaveform?
        let technicalMetadata = await EditorMediaTechnicalMetadata.load(asset)

        guard !Task.isCancelled else { return nil }
        if asset.isVideo, request.purpose != .metadata {
            let generator = AVAssetImageGenerator(asset: avAsset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 0, height: 120)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

            let posterTime = CMTime(seconds: min(0.1, seconds), preferredTimescale: 600)
            poster = await withTaskCancellationHandler {
                try? await generator.image(at: posterTime).image
            } onCancel: {
                generator.cancelAllCGImageGeneration()
            }
        }
        guard !Task.isCancelled else { return nil }
        if request.purpose == .editor || (asset.isAudio && request.purpose == .library) {
            waveform = await EditorAudioWaveform.load(.init(asset: avAsset, duration: seconds))
        }

        return EditorLoadedMedia(
            id: asset.id,
            duration: seconds,
            fileSize: fileSize,
            poster: poster,
            waveform: waveform,
            technicalMetadata: technicalMetadata
        )
    }

    nonisolated private static func loadFilmstripFrames(
        request: EditorFilmstripLoadRequest
    ) async -> [CGImage] {
        guard request.frameCount > 0 else { return [] }
        let avAsset = AVURLAsset(url: request.url)
        guard let duration = try? await avAsset.load(.duration) else { return [] }
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else { return [] }

        let generator = AVAssetImageGenerator(asset: avAsset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 0, height: 120)
        let step = seconds / Double(request.frameCount)
        let tolerance = min(0.5, max(1.0 / 120.0, step * 0.2))
        generator.requestedTimeToleranceBefore = CMTime(seconds: tolerance, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: tolerance, preferredTimescale: 600)

        let times = (0..<request.frameCount).map { index in
            CMTime(
                seconds: seconds * (Double(index) + 0.5) / Double(request.frameCount),
                preferredTimescale: 600
            )
        }
        return await withTaskCancellationHandler {
            var generated: [(time: Double, image: CGImage)] = []
            for await result in generator.images(for: times) {
                guard !Task.isCancelled else { return [] }
                if case let .success(requestedTime, image, _) = result {
                    generated.append((time: requestedTime.seconds, image: image))
                }
            }
            return generated
                .sorted { $0.time < $1.time }
                .map(\.image)
        } onCancel: {
            generator.cancelAllCGImageGeneration()
        }
    }
}

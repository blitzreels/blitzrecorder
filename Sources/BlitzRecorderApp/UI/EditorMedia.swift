import AppKit
import AVFoundation
import Foundation
import Observation
import SwiftUI

enum EditorSelection: Equatable {
    case segment(Int)
    case asset(String)
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
        case .screen: return "display"
        case .camera: return "video"
        case .microphone: return "mic"
        case .systemAudio: return "speaker.wave.2"
        case .other: return "doc"
        }
    }

    var tint: Color {
        switch kind {
        case .output, .screen: return BlitzUI.trackScreen
        case .camera: return BlitzUI.trackCamera
        case .microphone: return BlitzUI.trackMicrophone
        case .systemAudio: return BlitzUI.trackSystemAudio
        case .other: return Color.white.opacity(0.5)
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

struct EditorMediaTechnicalMetadata: Equatable, Sendable {
    let format: String
    let quality: String
}

private struct EditorLoadedMedia: Sendable {
    let id: String
    let duration: Double
    let fileSize: String
    let poster: CGImage?
    let filmstrip: [CGImage]
    let waveform: [Float]
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
    private(set) var durations: [String: Double] = [:]
    private(set) var fileSizes: [String: String] = [:]
    private(set) var technicalMetadata: [String: EditorMediaTechnicalMetadata] = [:]

    @ObservationIgnored private var loadingIDs: Set<String> = []
    @ObservationIgnored private var filmstripLoadingCounts: [String: Int] = [:]

    func loadAssets(_ assets: [EditorAsset]) async {
        let pending = assets.filter {
            $0.exists
                && $0.isPlayable
                && (durations[$0.id] == nil || technicalMetadata[$0.id] == nil)
                && !loadingIDs.contains($0.id)
        }
        guard !pending.isEmpty else { return }
        loadingIDs.formUnion(pending.map(\.id))
        defer { loadingIDs.subtract(pending.map(\.id)) }

        await withTaskGroup(of: EditorLoadedMedia?.self) { group in
            for asset in pending {
                group.addTask {
                    await Self.load(asset: asset)
                }
            }
            for await loaded in group {
                guard let loaded else { continue }
                durations[loaded.id] = loaded.duration
                fileSizes[loaded.id] = loaded.fileSize
                technicalMetadata[loaded.id] = loaded.technicalMetadata
                if let poster = loaded.poster {
                    posters[loaded.id] = poster
                }
                if loaded.filmstrip.count > (filmstrips[loaded.id]?.count ?? 0) {
                    filmstrips[loaded.id] = loaded.filmstrip
                }
                if !loaded.waveform.isEmpty {
                    waveforms[loaded.id] = loaded.waveform
                }
            }
        }
    }

    func loadFilmstrip(request: EditorFilmstripLoadRequest) async {
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

    nonisolated private static func load(asset: EditorAsset) async -> EditorLoadedMedia? {
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
        var filmstrip: [CGImage] = []
        var waveform: [Float] = []
        let technicalMetadata = await technicalMetadata(asset)

        if asset.isVideo {
            let generator = AVAssetImageGenerator(asset: avAsset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 0, height: 120)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

            let posterTime = CMTime(seconds: min(0.1, seconds), preferredTimescale: 600)
            poster = try? await generator.image(at: posterTime).image

            if seconds > 0 {
                let frameCount = 16
                for index in 0..<frameCount {
                    let time = CMTime(
                        seconds: seconds * (Double(index) + 0.5) / Double(frameCount),
                        preferredTimescale: 600
                    )
                    if let frame = try? await generator.image(at: time).image {
                        filmstrip.append(frame)
                    }
                }
            }
        } else if asset.isAudio {
            waveform = await Self.waveform(for: avAsset, duration: seconds)
        }

        return EditorLoadedMedia(
            id: asset.id,
            duration: seconds,
            fileSize: fileSize,
            poster: poster,
            filmstrip: filmstrip,
            waveform: waveform,
            technicalMetadata: technicalMetadata
        )
    }

    nonisolated private static func technicalMetadata(
        _ asset: EditorAsset
    ) async -> EditorMediaTechnicalMetadata {
        let avAsset = AVURLAsset(url: asset.url)
        let container = asset.url.pathExtension.uppercased()
        if asset.isVideo,
           let track = try? await avAsset.loadTracks(withMediaType: .video).first {
            let naturalSize = (try? await track.load(.naturalSize)) ?? .zero
            let transform = (try? await track.load(.preferredTransform)) ?? .identity
            let orientedRect = CGRect(origin: .zero, size: naturalSize).applying(transform)
            let width = Int(abs(orientedRect.width).rounded())
            let height = Int(abs(orientedRect.height).rounded())
            let frameRate = (try? await track.load(.nominalFrameRate)) ?? 0
            let dataRate = (try? await track.load(.estimatedDataRate)) ?? 0
            let descriptions = try? await track.load(.formatDescriptions)
            let codec = descriptions?.first.map {
                videoCodecLabel(CMFormatDescriptionGetMediaSubType($0))
            } ?? "Video"
            var quality = width > 0 && height > 0 ? ["\(width) × \(height)"] : []
            if frameRate > 0 {
                quality.append("\(Int(frameRate.rounded())) fps")
            }
            if dataRate > 0 {
                quality.append(String(format: "%.1f Mbps", dataRate / 1_000_000))
            }
            return EditorMediaTechnicalMetadata(
                format: [container, codec].filter { !$0.isEmpty }.joined(separator: " · "),
                quality: quality.isEmpty ? "Video quality unavailable" : quality.joined(separator: " · ")
            )
        }

        if asset.isAudio,
           let track = try? await avAsset.loadTracks(withMediaType: .audio).first {
            let descriptions = try? await track.load(.formatDescriptions)
            let formatDescription = descriptions?.first
            let codec = formatDescription.map {
                audioCodecLabel(CMFormatDescriptionGetMediaSubType($0))
            } ?? "Audio"
            let basicDescription = formatDescription.flatMap {
                CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee
            }
            let dataRate = (try? await track.load(.estimatedDataRate)) ?? 0
            var quality: [String] = []
            if let sampleRate = basicDescription?.mSampleRate, sampleRate > 0 {
                quality.append("\(Int((sampleRate / 1_000).rounded())) kHz")
            }
            if let channelCount = basicDescription?.mChannelsPerFrame {
                if channelCount == 1 {
                    quality.append("Mono")
                } else if channelCount == 2 {
                    quality.append("Stereo")
                } else {
                    quality.append("\(channelCount) channels")
                }
            }
            if dataRate > 0 {
                quality.append("\(Int((dataRate / 1_000).rounded())) kbps")
            }
            return EditorMediaTechnicalMetadata(
                format: [container, codec].filter { !$0.isEmpty }.joined(separator: " · "),
                quality: quality.isEmpty ? "Audio quality unavailable" : quality.joined(separator: " · ")
            )
        }

        return EditorMediaTechnicalMetadata(
            format: container.isEmpty ? "Unknown format" : container,
            quality: "Media details unavailable"
        )
    }

    nonisolated private static func videoCodecLabel(
        _ codec: FourCharCode
    ) -> String {
        switch codec {
        case kCMVideoCodecType_HEVC: return "HEVC"
        case kCMVideoCodecType_H264: return "H.264"
        case kCMVideoCodecType_AppleProRes422: return "ProRes 422"
        case kCMVideoCodecType_AppleProRes4444: return "ProRes 4444"
        default: return fourCharacterCode(codec)
        }
    }

    nonisolated private static func audioCodecLabel(
        _ codec: FourCharCode
    ) -> String {
        switch codec {
        case kAudioFormatMPEG4AAC: return "AAC"
        case kAudioFormatLinearPCM: return "PCM"
        case kAudioFormatMPEGLayer3: return "MP3"
        case kAudioFormatAppleLossless: return "Apple Lossless"
        default: return fourCharacterCode(codec)
        }
    }

    nonisolated private static func fourCharacterCode(
        _ value: FourCharCode
    ) -> String {
        let characters = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
        let label = String(bytes: characters, encoding: .ascii)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        return label.isEmpty ? "Unknown codec" : label
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
    }

    nonisolated private static func waveform(for avAsset: AVURLAsset, duration: Double) async -> [Float] {
        guard duration > 0,
              let track = try? await avAsset.loadTracks(withMediaType: .audio).first else {
            return []
        }

        var sampleRate = 44_100.0
        var channelCount = 1
        if let descriptions = try? await track.load(.formatDescriptions),
           let description = descriptions.first,
           let basicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee {
            if basicDescription.mSampleRate > 0 {
                sampleRate = basicDescription.mSampleRate
            }
            channelCount = max(1, Int(basicDescription.mChannelsPerFrame))
        }

        guard let reader = try? AVAssetReader(asset: avAsset) else { return [] }
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        guard reader.startReading() else { return [] }

        let bucketCount = 240
        var buckets = [Float](repeating: 0, count: bucketCount)
        let totalFrames = max(1, Int(duration * sampleRate))
        let frameStride = min(
            max(1, Int(sampleRate / 100)),
            max(1, totalFrames / (bucketCount * 12))
        )
        var frameIndex = 0

        while reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() {
            if Task.isCancelled {
                reader.cancelReading()
                return []
            }
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            let sampleCount = length / MemoryLayout<Float>.size
            guard sampleCount > 0 else { continue }

            var samples = [Float](repeating: 0, count: sampleCount)
            let status = samples.withUnsafeMutableBytes { destination in
                CMBlockBufferCopyDataBytes(
                    blockBuffer,
                    atOffset: 0,
                    dataLength: sampleCount * MemoryLayout<Float>.size,
                    destination: destination.baseAddress!
                )
            }
            guard status == kCMBlockBufferNoErr else { continue }

            let bufferFrameCount = sampleCount / channelCount
            for frame in stride(from: 0, to: bufferFrameCount, by: frameStride) {
                var peak: Float = 0
                for channel in 0..<channelCount {
                    let sample = abs(samples[frame * channelCount + channel])
                    if sample > peak {
                        peak = sample
                    }
                }
                let absoluteFrameIndex = frameIndex + frame
                let bucket = min(
                    bucketCount - 1,
                    max(0, absoluteFrameIndex * bucketCount / totalFrames)
                )
                if peak > buckets[bucket] {
                    buckets[bucket] = peak
                }
            }
            frameIndex += bufferFrameCount
        }

        guard reader.status == .completed else { return [] }

        if let maxValue = buckets.max(), maxValue > 0 {
            for index in buckets.indices {
                buckets[index] /= maxValue
            }
        }
        return buckets
    }
}

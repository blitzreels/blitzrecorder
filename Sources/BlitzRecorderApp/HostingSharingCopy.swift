import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

private let sharingCopyFailure = HostingFailure(message: "This video could not be prepared for sharing.")

enum HostingSharingCopy {
    struct Request {
        let fileURL: URL
        let progress: @Sendable (HostingClient.Progress) async -> Void
    }

    static func prepare(_ request: Request) async throws -> URL {
        try Task.checkCancellation()
        let asset = AVURLAsset(url: request.fileURL)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0,
              let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw HostingFailure(message: "This video has no playable video track.")
        }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let bounds = CGRect(origin: .zero, size: size).applying(transform)
        let displaySize = bounds.size
        let codec = try await track.load(.formatDescriptions).first.map(CMFormatDescriptionGetMediaSubType)
        var audioIsAAC = true
        for audio in try await asset.loadTracks(withMediaType: .audio) {
            let format = try await audio.load(.formatDescriptions).first.map(CMFormatDescriptionGetMediaSubType)
            audioIsAAC = audioIsAAC && format == kAudioFormatMPEG4AAC
        }
        let browserReady = min(displaySize.width, displaySize.height) <= 1080 && max(displaySize.width, displaySize.height) <= 1920
            && codec == kCMVideoCodecType_H264 && audioIsAAC
        if browserReady, request.fileURL.pathExtension.lowercased() == "mp4" { return request.fileURL }
        let fingerprint = try HostingExportMetadata.fingerprint(request.fileURL)
        let directory = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true).appendingPathComponent("BlitzRecorder/Sharing1080-h264-v1", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cached = directory.appendingPathComponent(fingerprint).appendingPathExtension("mp4")
        if FileManager.default.fileExists(atPath: cached.path) { return cached }
        let output = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        await request.progress(.optimizing(0))
        do {
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                if browserReady {
                    try await remux(asset, to: output)
                } else {
                    try await encode(.init(source: .init(asset: asset, track: track, transform: transform,
                        displaySize: displaySize, bounds: bounds), output: output, kind: .sharing, progress: request.progress))
                }
            } onCancel: {}
            try Task.checkCancellation()
            guard try HostingExportMetadata.fingerprint(request.fileURL) == fingerprint else {
                throw HostingFailure(message: "The video changed while preparing the sharing copy. Try again.")
            }
            if FileManager.default.fileExists(atPath: cached.path) {
                try FileManager.default.removeItem(at: output)
            } else {
                try FileManager.default.moveItem(at: output, to: cached)
            }
            await request.progress(.optimizing(1))
            return cached
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }

    private static func remux(_ asset: AVAsset, to output: URL) async throws {
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw sharingCopyFailure
        }
        exporter.shouldOptimizeForNetworkUse = true
        exporter.metadata = []
        try await exporter.export(to: output, as: .mp4)
    }

    private struct EncodeSource {
        let asset: AVAsset
        let track: AVAssetTrack
        let transform: CGAffineTransform
        let displaySize: CGSize
        let bounds: CGRect

        init(asset: AVAsset, track: AVAssetTrack, transform: CGAffineTransform, displaySize: CGSize, bounds: CGRect) {
            self.asset = asset
            self.track = track
            self.transform = transform
            self.displaySize = displaySize
            self.bounds = bounds
        }

        init(_ asset: AVAsset) async throws {
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw sharingCopyFailure }
            let (size, transform) = try await track.load(.naturalSize, .preferredTransform)
            let bounds = CGRect(origin: .zero, size: size).applying(transform)
            self.init(asset: asset, track: track, transform: transform, displaySize: bounds.size, bounds: bounds)
        }
    }

    private enum EncodeKind {
        /// The whole video, scaled only when a side exceeds 1080p.
        case sharing
        /// The first minute at up to 720p and 1.5 Mbit/s: the clip link previews (Discord, iMessage) play.
        case preview

        var shortSide: CGFloat { self == .sharing ? 1080 : 720 }
        var longSide: CGFloat { self == .sharing ? 1920 : 1280 }
        var seconds: Double? { self == .sharing ? nil : 60 }
        var audioBitrate: Int { self == .sharing ? 160_000 : 128_000 }
    }

    private struct EncodeJob {
        let source: EncodeSource
        let output: URL
        let kind: EncodeKind
        let progress: @Sendable (HostingClient.Progress) async -> Void
    }

    /// Hardware H.264. Keeps the source frame rate and scales only when a side exceeds the kind's limit.
    private static func encode(_ job: EncodeJob) async throws {
        let (asset, track, transform, displaySize, bounds) = (job.source.asset, job.source.track, job.source.transform,
                                                              job.source.displaySize, job.source.bounds)
        let output = job.output
        let progress = job.progress
        let scale = min(1, job.kind.shortSide / min(displaySize.width, displaySize.height),
                        job.kind.longSide / max(displaySize.width, displaySize.height))
        let renderSize = CGSize(width: max(2, floor(displaySize.width * scale / 2) * 2),
                                height: max(2, floor(displaySize.height * scale / 2) * 2))
        let composition = AVMutableVideoComposition()
        composition.renderSize = renderSize
        let frameDuration = try await track.load(.minFrameDuration)
        let nominalFPS = try await track.load(.nominalFrameRate)
        let fps = max(1, Int((nominalFPS > 0 ? nominalFPS : 30).rounded()))
        composition.frameDuration = frameDuration.isNumeric && frameDuration.seconds > 0
            ? frameDuration : CMTime(seconds: 1 / Double(fps), preferredTimescale: 60_000)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: try await asset.load(.duration))
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(transform.concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale)), at: .zero)
        instruction.layerInstructions = [layer]
        composition.instructions = [instruction]

        let reader = try AVAssetReader(asset: asset)
        let videoOutput = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        videoOutput.videoComposition = composition
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else {
            throw sharingCopyFailure
        }
        reader.add(videoOutput)

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let audioOutput: AVAssetReaderAudioMixOutput? = audioTracks.isEmpty ? nil : AVAssetReaderAudioMixOutput(
            audioTracks: audioTracks,
            audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ])
        if let audioOutput {
            guard reader.canAdd(audioOutput) else {
                throw sharingCopyFailure
            }
            reader.add(audioOutput)
        }

        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let pixels = Int(renderSize.width) * Int(renderSize.height)
        let reference = SocialVideoEncoding.videoBitrate(resolution: .p1080, fps: min(fps, 60))
        let bitrate = job.kind == .preview ? 1_500_000
            : max(1_500_000, Int((Double(reference) * max(0.15, Double(pixels) / Double(1920 * 1080))).rounded()))
        let hardware = HardwareVideoEncoderSupport.probe(HardwareVideoEncoderProbeRequest(
            width: Int(renderSize.width), height: Int(renderSize.height), codecType: kCMVideoCodecType_H264))
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: OptimizedCompositionExporter.videoOutputSettings(for: .init(
            width: Int(renderSize.width), height: Int(renderSize.height), bitrate: bitrate, framesPerSecond: fps,
            hardwareEncoderAvailable: hardware.isAvailable, codec: .h264, compressionQuality: nil,
            usesAverageBitRate: true, maxKeyFrameInterval: fps * 2, prioritizesSpeed: true)))
        guard writer.canAdd(videoInput) else {
            throw sharingCopyFailure
        }
        writer.add(videoInput)
        let audioInput: AVAssetWriterInput? = audioOutput == nil ? nil : AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: job.kind.audioBitrate
        ])
        if let audioInput {
            guard writer.canAdd(audioInput) else {
                throw sharingCopyFailure
            }
            writer.add(audioInput)
        }
        let fullDuration = (try await asset.load(.duration)).seconds
        let duration = max(0.001, min(fullDuration, job.kind.seconds ?? fullDuration))
        if job.kind.seconds != nil {
            reader.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: duration, preferredTimescale: 600))
        }
        guard writer.startWriting(), reader.startReading() else {
            throw writer.error ?? reader.error ?? sharingCopyFailure
        }
        writer.startSession(atSourceTime: .zero)
        try await SharingMediaPump.run(reader: reader, writer: writer, videoOutput: videoOutput, videoInput: videoInput,
                                       audioOutput: audioOutput, audioInput: audioInput, duration: duration, progress: progress)
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? sharingCopyFailure
        }
    }

    static let previewMaxBytes = 16 * 1024 * 1024

    /// The link-preview clip for a sharing copy, made once per file and cached. Nil when it can't be made or comes
    /// out too large; sharing never waits on it.
    static func preview(_ fileURL: URL) async -> URL? {
        do {
            let fingerprint = try HostingExportMetadata.fingerprint(fileURL)
            let directory = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true).appendingPathComponent("BlitzRecorder/SharingPreview-v1", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let cached = directory.appendingPathComponent(fingerprint).appendingPathExtension("mp4")
            if !FileManager.default.fileExists(atPath: cached.path) {
                let output = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
                defer { try? FileManager.default.removeItem(at: output) }
                try await encode(.init(source: try await EncodeSource(AVURLAsset(url: fileURL)), output: output,
                                       kind: .preview, progress: { _ in }))
                try FileManager.default.moveItem(at: output, to: cached)
            }
            let bytes = try cached.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            return (16...previewMaxBytes).contains(bytes) ? cached : nil
        } catch {
            return nil
        }
    }

    struct Playable: Equatable {
        let width: Int
        let height: Int
        let frameRate: Double?
    }

    static func playable(_ fileURL: URL) async throws -> Playable {
        guard let track = try await AVURLAsset(url: fileURL).loadTracks(withMediaType: .video).first else {
            throw sharingCopyFailure
        }
        let (size, transform, fps) = try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate)
        let display = CGRect(origin: .zero, size: size).applying(transform).size
        return Playable(width: Int(display.width.rounded()), height: Int(display.height.rounded()),
                        frameRate: fps > 0 && fps <= 240 ? Double(fps) : nil)
    }

    static func poster(_ fileURL: URL) async -> Data? {
        let asset = AVURLAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 960)
        guard let duration = try? await asset.load(.duration).seconds, duration.isFinite,
              let image = try? await generator.image(at: CMTime(seconds: min(1, duration / 2), preferredTimescale: 600)).image else {
            return nil
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination), data.length <= 1024 * 1024 else { return nil }
        return data as Data
    }
}

private final class SharingMediaPump: @unchecked Sendable {
    private let reader: AVAssetReader
    private let writer: AVAssetWriter
    private let videoOutput: AVAssetReaderOutput
    private let videoInput: AVAssetWriterInput
    private let audioOutput: AVAssetReaderOutput?
    private let audioInput: AVAssetWriterInput?
    private let duration: Double
    private let progress: @Sendable (HostingClient.Progress) async -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var videoDone = false
    private var audioDone = false
    private var resumed = false

    private var lastProgress = ContinuousClock.now

    init(reader: AVAssetReader, writer: AVAssetWriter, videoOutput: AVAssetReaderOutput, videoInput: AVAssetWriterInput,
         audioOutput: AVAssetReaderOutput?, audioInput: AVAssetWriterInput?, duration: Double,
         progress: @escaping @Sendable (HostingClient.Progress) async -> Void) {
        self.reader = reader
        self.writer = writer
        self.videoOutput = videoOutput
        self.videoInput = videoInput
        self.audioOutput = audioOutput
        self.audioInput = audioInput
        self.duration = duration
        self.progress = progress
        self.audioDone = audioOutput == nil
    }

    static func run(reader: AVAssetReader, writer: AVAssetWriter, videoOutput: AVAssetReaderOutput, videoInput: AVAssetWriterInput,
                    audioOutput: AVAssetReaderOutput?, audioInput: AVAssetWriterInput?, duration: Double,
                    progress: @escaping @Sendable (HostingClient.Progress) async -> Void) async throws {
        let pump = SharingMediaPump(reader: reader, writer: writer, videoOutput: videoOutput, videoInput: videoInput,
                                    audioOutput: audioOutput, audioInput: audioInput, duration: duration, progress: progress)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                pump.start(continuation)
            }
        } onCancel: { pump.cancel() }
    }

    private func start(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
        videoInput.requestMediaDataWhenReady(on: DispatchQueue(label: "hosting.share.video")) { [weak self] in
            self?.drain(self?.videoOutput, into: self?.videoInput, video: true)
        }
        if let audioInput, let audioOutput {
            audioInput.requestMediaDataWhenReady(on: DispatchQueue(label: "hosting.share.audio")) { [weak self] in
                self?.drain(audioOutput, into: audioInput, video: false)
            }
        }
    }

    private func cancel() {
        reader.cancelReading()
        writer.cancelWriting()
        finish(.failure(CancellationError()))
    }

    private func drain(_ output: AVAssetReaderOutput?, into input: AVAssetWriterInput?, video: Bool) {
        guard let output, let input else { return }
        lock.lock()
        let alreadyDone = video ? videoDone : audioDone
        lock.unlock()
        if alreadyDone { return }
        while input.isReadyForMoreMediaData {
            if Task.isCancelled {
                cancel()
                return
            }
            guard let sample = output.copyNextSampleBuffer() else {
                input.markAsFinished()
                if reader.status == .failed {
                    finish(.failure(reader.error ?? sharingCopyFailure))
                } else {
                    markDone(video: video)
                }
                return
            }
            guard input.append(sample) else {
                finish(.failure(writer.error ?? sharingCopyFailure))
                return
            }
            guard video else { continue }
            let time = CMSampleBufferGetPresentationTimeStamp(sample)
            guard time.isValid else { continue }
            let now = ContinuousClock.now
            lock.lock()
            let shouldReport = now >= lastProgress.advanced(by: .milliseconds(100))
            if shouldReport { lastProgress = now }
            lock.unlock()
            guard shouldReport else { continue }
            let fraction = min(0.99, max(0, time.seconds / duration))
            let report = progress
            Task { await report(.optimizing(fraction)) }
        }
    }

    private func markDone(video: Bool) {
        lock.lock()
        if video { videoDone = true } else { audioDone = true }
        let finished = videoDone && audioDone
        lock.unlock()
        if finished { finish(.success(())) }
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        guard !resumed, let continuation else {
            lock.unlock()
            return
        }
        resumed = true
        lock.unlock()
        continuation.resume(with: result)
    }
}

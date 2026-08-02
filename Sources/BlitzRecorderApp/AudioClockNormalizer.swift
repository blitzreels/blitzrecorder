import AVFoundation
import CoreMedia
import Foundation

struct AudioClockNormalizationRequest {
    let url: URL
    let format: SourceAudioFormat
    let bitrate: Int
    let measurement: CaptureClockRateMeasurement
}

struct AudioClockNormalizationResult: Equatable {
    let didCorrect: Bool
    let sourceDuration: CMTime
    let correctedDuration: CMTime
    let accumulatedDrift: CMTime
}

enum AudioClockNormalizer {
    private static let minimumMeasuredDurationSeconds = 10.0
    private static let minimumCorrectionSeconds = 0.02
    private static let minimumSafeRate = 0.98
    private static let maximumSafeRate = 1.02

    static func normalize(_ request: AudioClockNormalizationRequest) async throws -> AudioClockNormalizationResult {
        let asset = AVURLAsset(url: request.url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let sourceTrack = tracks.first else {
            throw RecorderError.mediaWriteFailed("Microphone audio has no readable track.")
        }
        let sourceTimeRange = try await sourceTrack.load(.timeRange)
        let sourceDuration = sourceTimeRange.duration
        let rate = request.measurement.masterTimePerSourceTime
        let correctedDuration = CMTimeMultiplyByFloat64(sourceDuration, multiplier: rate)
        let accumulatedDrift = CMTimeSubtract(correctedDuration, sourceDuration)
        let result = AudioClockNormalizationResult(
            didCorrect: false,
            sourceDuration: sourceDuration,
            correctedDuration: correctedDuration,
            accumulatedDrift: accumulatedDrift
        )

        guard request.measurement.sourceDuration.seconds >= minimumMeasuredDurationSeconds,
              abs(accumulatedDrift.seconds) >= minimumCorrectionSeconds else {
            return result
        }
        guard rate >= minimumSafeRate, rate <= maximumSafeRate else {
            throw RecorderError.mediaWriteFailed(
                "Microphone timing moved outside the safe synchronization range."
            )
        }

        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw RecorderError.exportUnavailable
        }
        try compositionTrack.insertTimeRange(sourceTimeRange, of: sourceTrack, at: .zero)
        compositionTrack.scaleTimeRange(
            CMTimeRange(start: .zero, duration: sourceDuration),
            toDuration: correctedDuration
        )

        let temporaryURL = request.url.deletingLastPathComponent().appendingPathComponent(
            ".\(request.url.deletingPathExtension().lastPathComponent)-sync-\(UUID().uuidString).\(request.format.fileExtension)"
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        try await render(.init(
            composition: composition,
            compositionTrack: compositionTrack,
            outputURL: temporaryURL,
            format: request.format,
            bitrate: request.bitrate,
            sourceTrack: sourceTrack
        ))
        try await validate(.init(
            url: temporaryURL,
            expectedDuration: correctedDuration
        ))
        _ = try FileManager.default.replaceItemAt(request.url, withItemAt: temporaryURL)
        return AudioClockNormalizationResult(
            didCorrect: true,
            sourceDuration: sourceDuration,
            correctedDuration: correctedDuration,
            accumulatedDrift: accumulatedDrift
        )
    }

    private static func render(_ request: AudioClockRenderRequest) async throws {
        try? FileManager.default.removeItem(at: request.outputURL)
        let reader = try AVAssetReader(asset: request.composition)
        let output = AVAssetReaderAudioMixOutput(
            audioTracks: [request.compositionTrack],
            audioSettings: [AVFormatIDKey: kAudioFormatLinearPCM]
        )
        output.audioTimePitchAlgorithm = .timeDomain
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw RecorderError.exportUnavailable
        }
        reader.add(output)

        let writer = try AVAssetWriter(outputURL: request.outputURL, fileType: request.format.avFileType)
        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: try await outputSettings(.init(
                format: request.format,
                bitrate: request.bitrate,
                sourceTrack: request.sourceTrack
            ))
        )
        guard writer.canAdd(input) else {
            throw RecorderError.writerNotReady
        }
        writer.add(input)

        guard writer.startWriting(), reader.startReading() else {
            throw writer.error ?? reader.error ?? RecorderError.writerNotReady
        }
        writer.startSession(atSourceTime: .zero)
        try await pump(.init(
            reader: reader,
            output: output,
            writer: writer,
            input: input
        ))
    }

    private static func pump(_ request: AudioClockRenderPumpRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            request.input.requestMediaDataWhenReady(
                on: DispatchQueue(label: "blitzrecorder.audio-clock-normalizer")
            ) {
                while request.input.isReadyForMoreMediaData {
                    guard let sampleBuffer = request.output.copyNextSampleBuffer() else {
                        request.input.markAsFinished()
                        if request.reader.status == .failed {
                            request.writer.cancelWriting()
                            continuation.resume(
                                throwing: request.reader.error ?? RecorderError.exportUnavailable
                            )
                            return
                        }
                        request.writer.finishWriting {
                            if request.writer.status == .completed {
                                continuation.resume()
                            } else {
                                continuation.resume(
                                    throwing: request.writer.error ?? RecorderError.writerNotReady
                                )
                            }
                        }
                        return
                    }
                    guard request.input.append(sampleBuffer) else {
                        request.reader.cancelReading()
                        request.writer.cancelWriting()
                        continuation.resume(
                            throwing: request.writer.error
                                ?? RecorderError.mediaWriteFailed(
                                    "Microphone synchronization writer rejected an audio sample."
                                )
                        )
                        return
                    }
                }
            }
        }
    }

    private static func outputSettings(_ request: AudioClockOutputSettingsRequest) async throws -> [String: Any] {
        let descriptions = try await request.sourceTrack.load(.formatDescriptions)
        let streamDescription = descriptions.first?.audioStreamBasicDescription
        let sampleRate = streamDescription?.mSampleRate ?? 48_000
        let channelCount = max(1, min(2, Int(streamDescription?.mChannelsPerFrame ?? 2)))
        if request.format.isLossless {
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channelCount,
                AVLinearPCMBitDepthKey: 24,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        }
        return [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVEncoderBitRateKey: channelCount == 1 ? request.bitrate / 2 : request.bitrate
        ]
    }

    private static func validate(_ request: AudioClockValidationRequest) async throws {
        let asset = AVURLAsset(url: request.url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let duration = try await asset.load(.duration)
        let tolerance = max(0.05, request.expectedDuration.seconds * 0.0001)
        guard !tracks.isEmpty,
              duration.isValid,
              abs(duration.seconds - request.expectedDuration.seconds) <= tolerance else {
            throw RecorderError.mediaWriteFailed(
                "Microphone synchronization output did not match the take clock."
            )
        }
    }
}

private struct AudioClockRenderRequest {
    let composition: AVMutableComposition
    let compositionTrack: AVMutableCompositionTrack
    let outputURL: URL
    let format: SourceAudioFormat
    let bitrate: Int
    let sourceTrack: AVAssetTrack
}

private struct AudioClockRenderPumpRequest: @unchecked Sendable {
    let reader: AVAssetReader
    let output: AVAssetReaderOutput
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
}

private struct AudioClockOutputSettingsRequest {
    let format: SourceAudioFormat
    let bitrate: Int
    let sourceTrack: AVAssetTrack
}

private struct AudioClockValidationRequest {
    let url: URL
    let expectedDuration: CMTime
}

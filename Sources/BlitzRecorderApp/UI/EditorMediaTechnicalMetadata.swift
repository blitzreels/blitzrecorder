import AVFoundation
import Foundation

struct EditorMediaTechnicalMetadata: Equatable, Sendable {
    let format: String
    let quality: String

    static func load(
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

    static func videoCodecLabel(
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

    private static func audioCodecLabel(
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

    private static func fourCharacterCode(
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
}

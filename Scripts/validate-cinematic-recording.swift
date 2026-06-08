#!/usr/bin/env swift
import AVFoundation
#if canImport(Cinematic)
import Cinematic
#endif
import CoreMedia
import Foundation

private struct Manifest: Decodable {
    var settings: Settings?
    var format: Format?
    var captureCodecLabel: String?
    var recordingDiagnostics: RecordingDiagnostics?
}

private struct Settings: Decodable {
    var cinematicVideoEnabled: Bool?
    var cinematicAperture: Double?
    var rotationDegrees: Int?
    var usesAutomaticRotation: Bool?
}

private struct Format: Decodable {
    var supportsCinematicVideo: Bool?
}

private struct RecordingDiagnostics: Decodable {
    var captureRotationDegrees: Int?
    var recordsOrientationAndMirroringChangesAsMetadataTrack: Bool?
    var cinematicVideoCaptureEnabled: Bool?
    var cinematicFocusMetadataEnabled: Bool?
    var simulatedAperture: Double?
    var recordedVideoCodecTypes: [String]?
    var recordedMetadataTrackCount: Int?
    var cinematicAssetVerified: Bool?
    var cinematicTrackCount: Int?
    var cinematicDurationSeconds: Double?
    var captureWarning: String?
}

private struct Options {
    var movieURL: URL?
    var manifestURL: URL?
    var expectsCinematic = false
    var json = false
}

private struct CheckResult: Encodable {
    var ok: Bool
    var failures: [String]
    var warnings: [String]
    var facts: [String: String]
}

private func usage() -> String {
    """
    Usage:
      swift Scripts/validate-cinematic-recording.swift <movie.mov> [--manifest manifest.json] [--expect-cinematic] [--json]

    Validates a transferred iPhone recording for Cinematic quality gates:
      - readable movie with video track
      - HEVC video codec when Cinematic was requested
      - Cinematic asset with video, disparity, and metadata tracks
      - positive Cinematic time range
      - manifest rotation/orientation diagnostics match the imported movie
      - optional manifest diagnostics agree with the asset

    If --manifest is omitted, the validator auto-loads:
      <movie-base>.remote-camera-manifest.json
    """
}

private func parseOptions(_ arguments: [String]) throws -> Options {
    var options = Options()
    var index = 1
    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "-h", "--help":
            print(usage())
            exit(0)
        case "--manifest":
            guard index + 1 < arguments.count else {
                throw ValidationError("Missing value after --manifest.")
            }
            index += 1
            options.manifestURL = URL(fileURLWithPath: arguments[index])
        case "--expect-cinematic":
            options.expectsCinematic = true
        case "--json":
            options.json = true
        default:
            guard !argument.hasPrefix("-") else {
                throw ValidationError("Unknown option: \(argument)")
            }
            guard options.movieURL == nil else {
                throw ValidationError("Only one movie path is supported.")
            }
            options.movieURL = URL(fileURLWithPath: argument)
        }
        index += 1
    }
    guard options.movieURL != nil else {
        throw ValidationError("Missing movie path.")
    }
    return options
}

private struct ValidationError: LocalizedError {
    var message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

private func loadManifest(from url: URL?) throws -> Manifest? {
    guard let url else { return nil }
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(Manifest.self, from: data)
}

private func inferredManifestURL(for movieURL: URL) -> URL? {
    let sidecarURL = movieURL
        .deletingPathExtension()
        .appendingPathExtension("remote-camera-manifest.json")
    return FileManager.default.fileExists(atPath: sidecarURL.path) ? sidecarURL : nil
}

private func codecLabel(for formatDescription: CMFormatDescription) -> String {
    let subtype = CMFormatDescriptionGetMediaSubType(formatDescription)
    switch subtype {
    case kCMVideoCodecType_HEVC:
        return "HEVC"
    case kCMVideoCodecType_H264:
        return "H.264"
    case kCMVideoCodecType_AppleProRes422:
        return "ProRes 422"
    case kCMVideoCodecType_AppleProRes4444:
        return "ProRes 4444"
    default:
        return fourCC(subtype)
    }
}

private func fourCC(_ code: FourCharCode) -> String {
    let scalars = [
        UInt8((code >> 24) & 0xff),
        UInt8((code >> 16) & 0xff),
        UInt8((code >> 8) & 0xff),
        UInt8(code & 0xff)
    ]
    let printable = scalars.allSatisfy { $0 >= 32 && $0 <= 126 }
    return printable ? String(bytes: scalars, encoding: .ascii) ?? "\(code)" : "\(code)"
}

private func isHEVCCodecLabel(_ label: String) -> Bool {
    label.localizedCaseInsensitiveContains("HEVC")
        || label == "hvc1"
        || label == "hev1"
}

private func validate(options: Options) async -> CheckResult {
    var failures: [String] = []
    var warnings: [String] = []
    var facts: [String: String] = [:]

    guard let movieURL = options.movieURL else {
        return CheckResult(ok: false, failures: ["Missing movie path."], warnings: [], facts: [:])
    }
    guard FileManager.default.fileExists(atPath: movieURL.path) else {
        return CheckResult(ok: false, failures: ["Movie does not exist: \(movieURL.path)"], warnings: [], facts: [:])
    }

    let manifestURL = options.manifestURL ?? inferredManifestURL(for: movieURL)
    if let manifestURL {
        facts["manifestPath"] = manifestURL.path
    }

    let manifest: Manifest?
    do {
        manifest = try loadManifest(from: manifestURL)
    } catch {
        return CheckResult(
            ok: false,
            failures: ["Could not decode manifest: \(error.localizedDescription)"],
            warnings: [],
            facts: [:]
        )
    }

    let expectsCinematic = options.expectsCinematic
        || manifest?.settings?.cinematicVideoEnabled == true
        || manifest?.recordingDiagnostics?.cinematicVideoCaptureEnabled == true

    let asset = AVURLAsset(url: movieURL)
    do {
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        facts["durationSeconds"] = durationSeconds.isFinite ? String(format: "%.3f", durationSeconds) : "unknown"

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            failures.append("Movie has no video track.")
            return CheckResult(ok: false, failures: failures, warnings: warnings, facts: facts)
        }
        let metadataTracks = try await asset.loadTracks(withMediaType: .metadata)
        facts["metadataTrackCount"] = "\(metadataTracks.count)"
        if let manifestMetadataTrackCount = manifest?.recordingDiagnostics?.recordedMetadataTrackCount {
            facts["manifestRecordedMetadataTrackCount"] = "\(manifestMetadataTrackCount)"
            if manifestMetadataTrackCount != metadataTracks.count {
                failures.append(
                    "Manifest recorded metadata track count \(manifestMetadataTrackCount), imported movie has \(metadataTracks.count)."
                )
            }
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        facts["videoSize"] = "\(Int(naturalSize.width))x\(Int(naturalSize.height))"
        facts["nominalFrameRate"] = nominalFrameRate > 0 ? String(format: "%.3f", nominalFrameRate) : "unknown"

        let formatDescriptions = try await videoTrack.load(.formatDescriptions)
        let codecLabels = formatDescriptions.map(codecLabel)
        facts["videoCodecs"] = codecLabels.isEmpty ? "unknown" : codecLabels.joined(separator: ", ")
        if let manifestVideoCodecs = manifest?.recordingDiagnostics?.recordedVideoCodecTypes,
           !manifestVideoCodecs.isEmpty {
            facts["manifestRecordedVideoCodecs"] = manifestVideoCodecs.joined(separator: ", ")
        }
        let hasHEVC = codecLabels.contains(where: isHEVCCodecLabel)

        if expectsCinematic && !hasHEVC {
            failures.append("Cinematic recording is not HEVC. Codecs: \(facts["videoCodecs"] ?? "unknown")")
        }
        if expectsCinematic, let diagnostics = manifest?.recordingDiagnostics {
            if let manifestVideoCodecs = diagnostics.recordedVideoCodecTypes {
                if !manifestVideoCodecs.contains(where: isHEVCCodecLabel) {
                    failures.append("Manifest says the saved iPhone movie was not HEVC.")
                }
            } else if diagnostics.cinematicVideoCaptureEnabled == true {
                failures.append("Manifest is missing saved-movie codec diagnostics for this Cinematic take.")
            }
        }
        if manifest?.format?.supportsCinematicVideo == false {
            failures.append("Manifest format says this recording was not Cinematic-capable.")
        }
        if manifest?.recordingDiagnostics?.cinematicVideoCaptureEnabled == false,
           manifest?.settings?.cinematicVideoEnabled == true {
            failures.append("Manifest says Cinematic was requested but not active.")
        }
        if expectsCinematic, let diagnostics = manifest?.recordingDiagnostics {
            if diagnostics.cinematicAssetVerified == false {
                failures.append("Manifest says the saved iPhone movie did not contain Cinematic depth metadata.")
            } else if diagnostics.cinematicVideoCaptureEnabled == true,
                      diagnostics.cinematicAssetVerified == nil {
                failures.append("Manifest is missing saved-movie Cinematic asset verification.")
            }
        }
        if let verified = manifest?.recordingDiagnostics?.cinematicAssetVerified {
            facts["manifestCinematicAssetVerified"] = "\(verified)"
        }
        if let trackCount = manifest?.recordingDiagnostics?.cinematicTrackCount {
            facts["manifestCinematicTrackCount"] = "\(trackCount)"
        }
        if let cinematicDuration = manifest?.recordingDiagnostics?.cinematicDurationSeconds {
            facts["manifestCinematicDurationSeconds"] = String(format: "%.3f", cinematicDuration)
        }
        if manifest?.recordingDiagnostics?.recordsOrientationAndMirroringChangesAsMetadataTrack == true,
           metadataTracks.isEmpty {
            failures.append("Manifest says orientation/mirroring metadata was recorded, but the imported movie has no metadata track.")
        }
        if manifest?.recordingDiagnostics?.recordsOrientationAndMirroringChangesAsMetadataTrack == false,
           manifest?.settings?.usesAutomaticRotation == true {
            failures.append("Automatic rotation was enabled, but the iPhone did not record orientation/mirroring metadata.")
        }
        if let requestedRotation = manifest?.settings?.rotationDegrees,
           let capturedRotation = manifest?.recordingDiagnostics?.captureRotationDegrees,
           normalizedRotationDegrees(requestedRotation) != normalizedRotationDegrees(capturedRotation) {
            failures.append(
                "Rotation mismatch. Requested \(normalizedRotationDegrees(requestedRotation)) degrees, recorded \(normalizedRotationDegrees(capturedRotation)) degrees."
            )
        }
        if manifest?.settings?.rotationDegrees != nil,
           manifest?.recordingDiagnostics?.captureRotationDegrees == nil {
            warnings.append("Manifest does not report the iPhone recording rotation.")
        }
        if manifest?.recordingDiagnostics?.cinematicFocusMetadataEnabled == false,
           manifest?.recordingDiagnostics?.cinematicVideoCaptureEnabled == true {
            warnings.append("Manifest says Cinematic focus metadata was unavailable during recording.")
        }
        if let requested = manifest?.settings?.cinematicAperture,
           let actual = manifest?.recordingDiagnostics?.simulatedAperture,
           abs(requested - actual) > 0.05 {
            failures.append(String(format: "Depth aperture mismatch. Requested f/%.1f, recorded f/%.1f.", requested, actual))
        }
        if let warning = manifest?.recordingDiagnostics?.captureWarning,
           !warning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            warnings.append("Manifest capture warning: \(warning)")
        }

        if expectsCinematic {
            await validateCinematicAsset(asset, failures: &failures, warnings: &warnings, facts: &facts)
        }
    } catch {
        failures.append("Could not inspect movie: \(error.localizedDescription)")
    }

    return CheckResult(ok: failures.isEmpty, failures: failures, warnings: warnings, facts: facts)
}

private func normalizedRotationDegrees(_ degrees: Int) -> Int {
    let remainder = degrees % 360
    return remainder >= 0 ? remainder : remainder + 360
}

private func validateCinematicAsset(
    _ asset: AVAsset,
    failures: inout [String],
    warnings: inout [String],
    facts: inout [String: String]
) async {
    #if canImport(Cinematic)
    if #available(macOS 14.0, *) {
        guard await CNAssetInfo.isCinematic(asset: asset) else {
            failures.append("Cinematic framework says this is not a Cinematic asset; depth metadata was lost.")
            return
        }
        do {
            let assetInfo = try await CNAssetInfo(asset: asset)
            facts["cinematicTrackCount"] = "\(assetInfo.allCinematicTracks.count)"
            let requiredTrackIDs = [
                assetInfo.cinematicVideoTrack.trackID,
                assetInfo.cinematicDisparityTrack.trackID,
                assetInfo.cinematicMetadataTrack.trackID
            ]
            if assetInfo.allCinematicTracks.isEmpty {
                failures.append("Cinematic asset has no Cinematic tracks.")
            }
            if requiredTrackIDs.contains(where: { $0 == 0 }) {
                failures.append("Cinematic asset is missing video, disparity, or metadata tracks.")
            }
            let cinematicDuration = assetInfo.timeRange.duration.seconds
            facts["cinematicDurationSeconds"] = cinematicDuration.isFinite
                ? String(format: "%.3f", cinematicDuration)
                : "unknown"
            if !cinematicDuration.isFinite || cinematicDuration <= 0 {
                failures.append("Cinematic asset has invalid Cinematic timing metadata.")
            }
        } catch {
            failures.append("Cinematic framework could not inspect asset: \(error.localizedDescription)")
        }
    } else {
        failures.append("Cinematic validation requires macOS 14 or later.")
    }
    #else
    failures.append("This Mac build cannot import the Cinematic framework.")
    #endif
}

private func printResult(_ result: CheckResult, asJSON: Bool) {
    if asJSON {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(result),
           let text = String(data: data, encoding: .utf8) {
            print(text)
        }
        return
    }

    print(result.ok ? "Cinematic recording validation passed." : "Cinematic recording validation failed.")
    for key in result.facts.keys.sorted() {
        print("fact: \(key)=\(result.facts[key] ?? "")")
    }
    for warning in result.warnings {
        print("warning: \(warning)")
    }
    for failure in result.failures {
        print("error: \(failure)")
    }
}

let semaphore = DispatchSemaphore(value: 0)
Task {
    let exitCode: Int
    do {
        let options = try parseOptions(CommandLine.arguments)
        let result = await validate(options: options)
        printResult(result, asJSON: options.json)
        exitCode = result.ok ? 0 : 1
    } catch {
        fputs("\(error.localizedDescription)\n\n\(usage())\n", stderr)
        exitCode = 2
    }
    Foundation.exit(Int32(exitCode))
    semaphore.signal()
}
dispatchMain()

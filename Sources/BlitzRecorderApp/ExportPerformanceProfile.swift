import Foundation

enum ExportPerformancePreset: String, CaseIterable {
    case fast
    case balanced
    case maximum
    case master
    case custom

    var displayName: String {
        switch self {
        case .fast:
            "Sharing"
        case .balanced:
            "Recommended"
        case .maximum:
            "Archive"
        case .master:
            "Master"
        case .custom:
            "Custom"
        }
    }

    var plainDescription: String {
        switch self {
        case .fast:
            "Small H.264 · 1080p · 30 fps"
        case .balanced:
            "Light loss · 1080p · source fps"
        case .maximum:
            "Visually lossless HEVC · source res"
        case .master:
            "ProRes 422 · source res · huge MOV"
        case .custom:
            "Set format, resolution, fps, and quality below"
        }
    }
}

struct ExportPerformanceProfile: Equatable {
    let preset: ExportPerformancePreset
    let resolution: OutputResolution
    let framesPerSecond: Int
    let videoQuality: ExportVideoQuality

    static func resolved(
        preset: ExportPerformancePreset,
        sourceResolution: OutputResolution,
        sourceFramesPerSecond: Int,
        customResolution: OutputResolution,
        customFramesPerSecond: Int,
        customVideoQuality: ExportVideoQuality
    ) -> ExportPerformanceProfile {
        let sourceFPS = normalizedFramesPerSecond(sourceFramesPerSecond)
        switch preset {
        case .fast:
            return ExportPerformanceProfile(
                preset: preset,
                resolution: .p1080,
                framesPerSecond: min(30, sourceFPS),
                videoQuality: .web
            )
        case .balanced:
            return ExportPerformanceProfile(
                preset: preset,
                resolution: .p1080,
                framesPerSecond: sourceFPS,
                videoQuality: .high
            )
        case .maximum:
            return ExportPerformanceProfile(
                preset: preset,
                resolution: sourceResolution,
                framesPerSecond: sourceFPS,
                videoQuality: .maximum
            )
        case .master:
            return ExportPerformanceProfile(
                preset: preset,
                resolution: sourceResolution,
                framesPerSecond: sourceFPS,
                videoQuality: .proRes
            )
        case .custom:
            return ExportPerformanceProfile(
                preset: preset,
                resolution: customResolution,
                framesPerSecond: normalizedFramesPerSecond(customFramesPerSecond),
                videoQuality: customVideoQuality
            )
        }
    }

    func applying(to settings: RecordingSettings) -> RecordingSettings {
        var settings = settings
        settings.outputResolution = resolution
        settings.framesPerSecond = framesPerSecond
        let dimensions = settings.outputResolution.dimensions(for: settings.layout)
        let encoding = videoQuality.encodingProfile(
            baseBitrate: settings.autoVideoBitrate,
            framesPerSecond: framesPerSecond,
            audioBitrate: settings.audioQuality.bitrate,
            width: dimensions.width,
            height: dimensions.height
        )
        settings.customVideoBitrate = encoding.bitrate
        settings.exportEncoding = encoding
        if let format = encoding.preferredFormat {
            settings.outputVideoFormat = format
        }
        if reducesExpensiveEffects {
            settings.screenShadowEnabled = false
            settings.cameraShadowEnabled = false
        }
        return settings
    }

    func applying(to scene: RecordingScene) -> RecordingScene {
        guard reducesExpensiveEffects else { return scene }
        var scene = scene
        scene.screenShadowEnabled = false
        scene.cameraShadowEnabled = false
        return scene
    }

    var reducesExpensiveEffects: Bool {
        false
    }

    private static func normalizedFramesPerSecond(_ value: Int) -> Int {
        if RecordingSettings.supportedFrameRates.contains(value) {
            return value
        }
        return value < 60 ? 30 : 60
    }
}

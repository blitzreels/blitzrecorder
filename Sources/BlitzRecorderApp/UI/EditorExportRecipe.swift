import Foundation

struct EditorExportRecipe {
    struct Request {
        let preset: ExportPerformancePreset
        let sourceResolution: OutputResolution
        let sourceFramesPerSecond: Int
        let customResolution: OutputResolution
        let customFramesPerSecond: Int
        let customVideoQuality: ExportVideoQuality
        let layout: CaptureLayout
        let layoutCount: Int
        let audioBitrate: Int
        let duration: Double
    }

    let profile: ExportPerformanceProfile
    let encoding: ExportEncodingProfile
    let summary: String
    let estimatedSize: String

    static func make(_ request: Request) -> EditorExportRecipe {
        let profile = ExportPerformanceProfile.resolved(
            preset: request.preset,
            sourceResolution: request.sourceResolution,
            sourceFramesPerSecond: request.sourceFramesPerSecond,
            customResolution: request.customResolution,
            customFramesPerSecond: request.customFramesPerSecond,
            customVideoQuality: request.customVideoQuality
        )
        let dimensions = profile.resolution.dimensions(for: request.layout)
        let encoding = profile.videoQuality.encodingProfile(
            baseBitrate: SocialVideoEncoding.videoBitrate(
                resolution: profile.resolution,
                fps: profile.framesPerSecond
            ),
            framesPerSecond: profile.framesPerSecond,
            audioBitrate: request.audioBitrate,
            width: dimensions.width,
            height: dimensions.height
        )
        let summary: String
        if request.layoutCount > 1 {
            summary = "\(request.layoutCount) videos · \(profile.resolution.displayName) · \(profile.framesPerSecond) fps"
        } else {
            summary = "\(dimensions.width) × \(dimensions.height) · \(profile.framesPerSecond) fps"
        }
        return EditorExportRecipe(
            profile: profile,
            encoding: encoding,
            summary: summary,
            estimatedSize: encoding.estimatedSizeText(
                duration: request.duration,
                layoutCount: max(1, request.layoutCount)
            )
        )
    }

    struct RestoredControls: Equatable {
        var preset: ExportPerformancePreset
        var format: OutputVideoFormat
        var resolution: OutputResolution
        var framesPerSecond: Int
        var quality: ExportVideoQuality
    }

    static func restored(
        snapshot: RecordingProject.ExportRecipeSnapshot?
    ) -> RestoredControls? {
        guard let snapshot,
              let preset = ExportPerformancePreset(rawValue: snapshot.preset),
              let format = OutputVideoFormat(rawValue: snapshot.format),
              let resolution = OutputResolution(rawValue: snapshot.resolution),
              let quality = ExportVideoQuality(rawValue: snapshot.quality) else {
            return nil
        }
        return RestoredControls(
            preset: preset,
            format: format,
            resolution: resolution,
            framesPerSecond: snapshot.framesPerSecond,
            quality: quality.resolvedMenuQuality
        )
    }

    static func fallbackFormat(
        projectFormat: String,
        fallbackFormat: OutputVideoFormat
    ) -> OutputVideoFormat {
        OutputVideoFormat(rawValue: projectFormat) ?? fallbackFormat
    }

    struct AppliedPreset: Equatable {
        var preset: ExportPerformancePreset
        var resolution: OutputResolution
        var framesPerSecond: Int
        var quality: ExportVideoQuality
        var format: OutputVideoFormat
    }

    static func applyingPreset(
        _ preset: ExportPerformancePreset,
        sourceResolution: OutputResolution,
        sourceFramesPerSecond: Int,
        customResolution: OutputResolution,
        customFramesPerSecond: Int,
        customQuality: ExportVideoQuality,
        currentFormat: OutputVideoFormat
    ) -> AppliedPreset {
        let profile = ExportPerformanceProfile.resolved(
            preset: preset,
            sourceResolution: sourceResolution,
            sourceFramesPerSecond: sourceFramesPerSecond,
            customResolution: customResolution,
            customFramesPerSecond: customFramesPerSecond,
            customVideoQuality: customQuality
        )
        return AppliedPreset(
            preset: preset,
            resolution: profile.resolution,
            framesPerSecond: profile.framesPerSecond,
            quality: profile.videoQuality,
            format: profile.videoQuality.resolvedOutputFormat(currentFormat)
        )
    }
}

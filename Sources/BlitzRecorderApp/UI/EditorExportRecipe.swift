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
        var playbackRate: Double = 1.0
        var destination: EditorExportDestination = .file
        /// Bytes per file. Missing means the quality tier decides the size.
        let targetFileSize: Int64?
    }

    let profile: ExportPerformanceProfile
    let encoding: ExportEncodingProfile
    let summary: String
    let estimatedSize: String
    /// One file, whatever the number of formats.
    let estimatedFileBytes: Int64
    let fileSizeRange: ClosedRange<Int64>
    /// Set when the chosen size leaves less detail than the Small tier at this resolution.
    let sizeWarning: String?

    static func make(_ request: Request) -> EditorExportRecipe {
        let sharing = request.destination == .link
        var profile = sharing ? shareProfile(request) : ExportPerformanceProfile.resolved(
            preset: request.preset,
            sourceResolution: request.sourceResolution,
            sourceFramesPerSecond: request.sourceFramesPerSecond,
            customResolution: request.customResolution,
            customFramesPerSecond: request.customFramesPerSecond,
            customVideoQuality: request.customVideoQuality
        )
        let dimensions = profile.resolution.dimensions(for: request.layout)
        var encoding = profile.videoQuality.encodingProfile(
            baseBitrate: SocialVideoEncoding.videoBitrate(
                resolution: profile.resolution,
                fps: profile.framesPerSecond
            ),
            framesPerSecond: profile.framesPerSecond,
            audioBitrate: request.audioBitrate,
            width: dimensions.width,
            height: dimensions.height
        )
        if sharing { encoding = encoding.prioritizingSpeed() }
        let rate = ExportPlaybackRate(clamping: request.playbackRate).value
        let seconds = max(0.1, request.duration / rate)
        let tierBitrate = encoding.bitrate
        if !sharing, encoding.codec != .proRes422, let target = request.targetFileSize {
            let requested = Double(target) * 8 / seconds - Double(encoding.audioBitrate)
            let videoBitrate = Int(min(Double(RecordingSettings.maxCustomVideoBitrate), max(0, requested)))
            encoding = encoding.withVideoBitrate(videoBitrate)
            profile = profile.withVideoBitrate(encoding.bitrate)
        }
        let smallBitrate = ExportVideoQuality.compact.videoBitrate(baseBitrate: SocialVideoEncoding.videoBitrate(
            resolution: profile.resolution, fps: profile.framesPerSecond))
        let highBitrate = ExportVideoQuality.high.videoBitrate(baseBitrate: SocialVideoEncoding.videoBitrate(
            resolution: profile.resolution, fps: profile.framesPerSecond))
        let lowest = encoding.withVideoBitrate(ExportEncodingProfile.minimumTargetBitrate)
            .estimatedBytes(duration: seconds, layoutCount: 1)
        let highest = encoding.withVideoBitrate(max(highBitrate * 2, tierBitrate))
            .estimatedBytes(duration: seconds, layoutCount: 1)
        let summary: String
        if request.layoutCount > 1 {
            summary = "\(request.layoutCount) videos · \(profile.resolution.displayName) · \(profile.framesPerSecond) fps\(Self.speedSuffix(request.playbackRate))"
        } else {
            summary = "\(dimensions.width) × \(dimensions.height) · \(profile.framesPerSecond) fps\(Self.speedSuffix(request.playbackRate))"
        }
        return EditorExportRecipe(
            profile: profile,
            encoding: encoding,
            summary: summary,
            estimatedSize: encoding.estimatedSizeText(duration: seconds, layoutCount: max(1, request.layoutCount)),
            estimatedFileBytes: encoding.estimatedBytes(duration: seconds, layoutCount: 1),
            fileSizeRange: lowest...max(lowest + 1, highest),
            sizeWarning: profile.videoBitrateOverride.map { $0 < smallBitrate } == true
                ? "Smaller than Small at \(profile.resolution.displayName). Text may look soft, so try a lower resolution."
                : nil
        )
    }

    /// The size each quality tier would produce at the resolution and frame rate the request resolves to.
    static func estimatedSize(_ request: Request, quality: ExportVideoQuality) -> String {
        let profile = make(request).profile
        return make(Request(
            preset: .custom,
            sourceResolution: request.sourceResolution,
            sourceFramesPerSecond: request.sourceFramesPerSecond,
            customResolution: profile.resolution,
            customFramesPerSecond: profile.framesPerSecond,
            customVideoQuality: quality,
            layout: request.layout,
            layoutCount: request.layoutCount,
            audioBitrate: request.audioBitrate,
            duration: request.duration,
            playbackRate: request.playbackRate,
            destination: request.destination,
            targetFileSize: nil
        )).estimatedSize
    }

    /// One hardware H.264 pass at the source rate, capped at 30 fps and 1080p. Already browser-ready, so sharing does not transcode again.
    private static func shareProfile(_ request: Request) -> ExportPerformanceProfile {
        let fps = request.sourceFramesPerSecond
        return ExportPerformanceProfile(
            preset: .fast,
            resolution: request.sourceResolution.height < 1080 ? request.sourceResolution : .p1080,
            framesPerSecond: min(30, max(1, fps)),
            videoQuality: .web)
    }

    struct RestoredControls: Equatable {
        var preset: ExportPerformancePreset
        var format: OutputVideoFormat
        var resolution: OutputResolution
        var framesPerSecond: Int
        var quality: ExportVideoQuality
        var playbackRate: ExportPlaybackRate
        var targetFileSize: Int64?
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
            quality: quality.resolvedMenuQuality,
            playbackRate: ExportPlaybackRate(clamping: snapshot.playbackRate),
            targetFileSize: snapshot.targetFileSize
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

    static func reused(_ record: RecordingProject.ExportRecord) -> AppliedPreset? {
        guard let quality = ExportVideoQuality(rawValue: record.quality),
              let resolution = OutputResolution(rawValue: record.resolution) else { return nil }
        let format = OutputVideoFormat(rawValue: record.format) ?? .mp4
        return AppliedPreset(
            preset: .custom,
            resolution: resolution,
            framesPerSecond: record.framesPerSecond,
            quality: quality.resolvedMenuQuality,
            format: quality.resolvedOutputFormat(format)
        )
    }

    private static func speedSuffix(_ rate: Double) -> String {
        let playbackRate = ExportPlaybackRate(clamping: rate)
        guard playbackRate != .normal else { return "" }
        return " · \(playbackRate.displayName)"
    }
}

enum EditorExportLayouts {
    struct Request {
        let current: CaptureLayout
        let additional: Set<CaptureLayout>
    }

    static func resolve(_ request: Request) -> [CaptureLayout] {
        CaptureLayout.allCases.filter { $0 == request.current || request.additional.contains($0) }
    }

    static func title(_ layout: CaptureLayout) -> String {
        switch layout {
        case .vertical: "Vertical"
        case .horizontal: "Landscape"
        case .square: "Square"
        }
    }
}

struct EditorOutputHistory {
    let exports: [RecordingProject.ExportRecord]
    let links: [HostedVideoShareController.ProjectLink]

    /// Files plus links that were not made from one of those files.
    var count: Int {
        exports.count + links.filter { link in !exports.contains(where: link.matches) }.count
    }
}

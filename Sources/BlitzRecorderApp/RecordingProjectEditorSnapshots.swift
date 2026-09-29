import Foundation

extension RecordingProject {
    struct ChapterSnapshot: Codable, Equatable, Identifiable {
        let id: UUID
        let time: Double
        let endTime: Double?
        let title: String
        let summary: String?
        let confidence: Double?

        init(
            id: UUID = UUID(),
            time: Double,
            endTime: Double? = nil,
            title: String,
            summary: String? = nil,
            confidence: Double? = nil
        ) {
            self.id = id
            self.time = time
            self.endTime = endTime
            self.title = title
            self.summary = summary
            self.confidence = confidence
        }
    }

    struct TimelineSnapshot: Codable, Equatable {
        struct Track: Codable, Equatable, Identifiable {
            let id: String
            let kind: String
            let title: String
            let sourceRole: String?
        }

        struct Clip: Codable, Equatable, Identifiable {
            let id: String
            let trackID: String
            let sourceRole: String?
            let time: Double
            let duration: Double?
            let startOffset: Double
            let frame: RectValue?
            let crop: RectValue?
            let opacity: Double?
            let layerOrder: Int?
        }

        struct Keyframe: Codable, Equatable, Identifiable {
            let id: String
            let clipID: String
            let property: String
            let time: Double
            let value: Double
            let easing: String?
        }

        let tracks: [Track]
        let clips: [Clip]
        let keyframes: [Keyframe]

        static let empty = TimelineSnapshot(tracks: [], clips: [], keyframes: [])
    }

    struct ExportRecipeSnapshot: Codable, Equatable {
        let preset: String
        let format: String
        let resolution: String
        let framesPerSecond: Int
        let quality: String
        var playbackRate: Double

        init(
            preset: String,
            format: String,
            resolution: String,
            framesPerSecond: Int,
            quality: String,
            playbackRate: Double = 1.0
        ) {
            self.preset = preset
            self.format = format
            self.resolution = resolution
            self.framesPerSecond = framesPerSecond
            self.quality = quality
            self.playbackRate = ExportPlaybackRate(clamping: playbackRate).value
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            preset = try container.decode(String.self, forKey: .preset)
            format = try container.decode(String.self, forKey: .format)
            resolution = try container.decode(String.self, forKey: .resolution)
            framesPerSecond = try container.decode(Int.self, forKey: .framesPerSecond)
            quality = try container.decode(String.self, forKey: .quality)
            playbackRate = ExportPlaybackRate(
                clamping: try container.decodeIfPresent(Double.self, forKey: .playbackRate) ?? 1.0
            ).value
        }
    }

    struct CutSnapshot: Codable, Equatable, Identifiable {
        let id: UUID
        let start: Double
        let end: Double
        let kind: String
        let source: String
        let enabled: Bool

        init(_ cut: TimelineCut) {
            id = cut.id
            start = cut.start
            end = cut.end
            kind = cut.kind.rawValue
            source = cut.source.rawValue
            enabled = cut.isEnabled
        }

        var cut: TimelineCut {
            TimelineCut(
                id: id,
                start: start,
                end: end,
                kind: TimelineCutKind(rawValue: kind) ?? .manual,
                source: TimelineCutSource(rawValue: source) ?? .user,
                isEnabled: enabled
            )
        }
    }

    struct TextOverlayStyleSnapshot: Codable, Equatable {
        let preset: String
        let size: Double
        let weight: String
        let color: String
        let background: String
        let alignment: String

        init(_ style: TextOverlayStyle) {
            preset = style.preset.rawValue
            size = style.size
            weight = style.weight.rawValue
            color = style.colorHex
            background = style.background.rawValue
            alignment = style.alignment.rawValue
        }

        var style: TextOverlayStyle {
            let resolvedPreset = TextOverlayPreset(rawValue: preset) ?? .caption
            let base = TextOverlayStyle.preset(resolvedPreset)
            return TextOverlayStyle(
                preset: resolvedPreset,
                size: size,
                weight: TextOverlayWeight(rawValue: weight) ?? base.weight,
                colorHex: color,
                background: TextOverlayBackground(rawValue: background) ?? base.background,
                alignment: TextOverlayAlignment(rawValue: alignment) ?? base.alignment
            )
        }
    }

    struct TextOverlaySnapshot: Codable, Equatable, Identifiable {
        let id: UUID
        let start: Double
        let end: Double
        let text: String
        let frame: RectValue
        let style: TextOverlayStyleSnapshot
        let fadeSeconds: Double

        init(_ overlay: TextOverlay) {
            id = overlay.id
            start = overlay.start
            end = overlay.end
            text = overlay.text
            frame = RectValue(overlay.frame)
            style = TextOverlayStyleSnapshot(overlay.style)
            fadeSeconds = overlay.fadeSeconds
        }

        var overlay: TextOverlay {
            TextOverlay(
                id: id,
                start: start,
                end: end,
                text: text,
                frame: frame.rect,
                style: style.style,
                fadeSeconds: fadeSeconds
            )
        }
    }

    struct ZoomTrackSnapshot: Codable, Equatable {
        struct Keyframe: Codable, Equatable, Identifiable {
            let id: UUID
            let time: Double
            let amount: Double
            let position: PointValue
            let easing: String

            init(_ keyframe: ScreenZoomKeyframe) {
                id = keyframe.id
                time = keyframe.time
                amount = keyframe.amount
                position = PointValue(keyframe.position)
                easing = keyframe.easing.rawValue
            }

            var keyframe: ScreenZoomKeyframe {
                ScreenZoomKeyframe(
                    id: id,
                    time: time,
                    amount: amount,
                    position: position.point,
                    easing: ScreenZoomEasing(rawValue: easing) ?? .easeInOut
                )
            }
        }

        let keyframes: [Keyframe]
        let generatedFromCursor: Bool
        let intensity: Double
        let isEnabled: Bool

        static let empty = ZoomTrackSnapshot(keyframes: [], generatedFromCursor: false, intensity: 2)

        init(keyframes: [Keyframe], generatedFromCursor: Bool, intensity: Double) {
            self.keyframes = keyframes
            self.generatedFromCursor = generatedFromCursor
            self.intensity = intensity
            self.isEnabled = true
        }

        init(_ track: ScreenZoomTrack) {
            keyframes = track.keyframes.map(Keyframe.init)
            generatedFromCursor = track.generatedFromCursor
            intensity = track.intensity
            isEnabled = track.isEnabled
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            keyframes = try container.decode([Keyframe].self, forKey: .keyframes)
            generatedFromCursor = try container.decode(Bool.self, forKey: .generatedFromCursor)
            intensity = try container.decode(Double.self, forKey: .intensity)
            isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        }

        var track: ScreenZoomTrack {
            var track = ScreenZoomTrack(
                keyframes: keyframes.map(\.keyframe),
                generatedFromCursor: generatedFromCursor,
                intensity: intensity
            )
            track.isEnabled = isEnabled
            return track
        }
    }

    struct TimelineEditsSnapshot: Codable, Equatable {
        let cuts: [CutSnapshot]
        let textOverlays: [TextOverlaySnapshot]
        let zoom: ZoomTrackSnapshot
        let videoSplits: [Double]
        let silenceRemovalApplied: Bool
        let silenceSettings: SilenceRemovalSettings?
        let silenceOverrides: [SilenceOverride]
        let cursorStyle: CursorPresentationStyle
        let voiceCleanup: VoiceCleanupSettings
        let outputVariants: [RecordingOutputVariant]
        let activeOutputLayout: CaptureLayout?
        let privacyMasks: [PrivacyMask]
        let cameraFollowsZoom: Bool

        static let empty = TimelineEditsSnapshot(cuts: [], textOverlays: [], zoom: .empty)

        init(cuts: [CutSnapshot], textOverlays: [TextOverlaySnapshot], zoom: ZoomTrackSnapshot) {
            self.cuts = cuts
            self.textOverlays = textOverlays
            self.zoom = zoom
            self.videoSplits = []
            self.silenceRemovalApplied = false
            self.silenceSettings = nil
            self.silenceOverrides = []
            self.cursorStyle = .standard
            self.cameraFollowsZoom = false
            self.privacyMasks = []
            self.outputVariants = []
            self.voiceCleanup = .disabled
            self.activeOutputLayout = nil
        }

        init(_ edits: TimelineEdits) {
            cuts = edits.cuts.map(CutSnapshot.init)
            textOverlays = edits.textOverlays.map(TextOverlaySnapshot.init)
            zoom = ZoomTrackSnapshot(edits.zoom)
            videoSplits = edits.videoSplits
            silenceRemovalApplied = edits.silenceRemovalApplied
            silenceSettings = edits.silenceSettings
            silenceOverrides = edits.silenceOverrides
            cursorStyle = edits.cursorStyle
            cameraFollowsZoom = edits.cameraFollowsZoom
            privacyMasks = edits.privacyMasks
            outputVariants = edits.outputVariants
            voiceCleanup = edits.voiceCleanup
            activeOutputLayout = edits.activeOutputLayout
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            cuts = try container.decodeIfPresent([CutSnapshot].self, forKey: .cuts) ?? []
            textOverlays = try container.decodeIfPresent([TextOverlaySnapshot].self, forKey: .textOverlays) ?? []
            zoom = try container.decodeIfPresent(ZoomTrackSnapshot.self, forKey: .zoom) ?? .empty
            videoSplits = try container.decodeIfPresent([Double].self, forKey: .videoSplits) ?? []
            silenceRemovalApplied = try container.decodeIfPresent(Bool.self, forKey: .silenceRemovalApplied)
                ?? cuts.contains { $0.cut.kind == .silence && $0.cut.isEnabled }
            silenceSettings = try container.decodeIfPresent(SilenceRemovalSettings.self, forKey: .silenceSettings)?.sanitized
            silenceOverrides = try container.decodeIfPresent([SilenceOverride].self, forKey: .silenceOverrides) ?? []
            cursorStyle = try container.decodeIfPresent(CursorPresentationStyle.self, forKey: .cursorStyle) ?? .standard
            voiceCleanup = try container.decodeIfPresent(VoiceCleanupSettings.self, forKey: .voiceCleanup) ?? .disabled
            outputVariants = try container.decodeIfPresent([RecordingOutputVariant].self, forKey: .outputVariants) ?? []
            activeOutputLayout = try container.decodeIfPresent(CaptureLayout.self, forKey: .activeOutputLayout)
            privacyMasks = try container.decodeIfPresent([PrivacyMask].self, forKey: .privacyMasks) ?? []
            cameraFollowsZoom = try container.decodeIfPresent(Bool.self, forKey: .cameraFollowsZoom) ?? false
        }

        var edits: TimelineEdits {
            TimelineEdits(
                cuts: cuts.map(\.cut),
                textOverlays: textOverlays.map(\.overlay),
                zoom: zoom.track,
                silenceOverrides: silenceOverrides,
                cursorStyle: cursorStyle,
                cameraFollowsZoom: cameraFollowsZoom,
                privacyMasks: privacyMasks,
                outputVariants: outputVariants,
                activeOutputLayout: activeOutputLayout,
                voiceCleanup: voiceCleanup,
                videoSplits: videoSplits,
                silenceRemovalApplied: silenceRemovalApplied,
                silenceSettings: silenceSettings
            )
        }

        var isEmpty: Bool {
            silenceSettings == nil && videoSplits.isEmpty && !silenceRemovalApplied && cuts.isEmpty && textOverlays.isEmpty && zoom.keyframes.isEmpty && silenceOverrides.isEmpty
                && cursorStyle == .standard && !cameraFollowsZoom && privacyMasks.isEmpty && outputVariants.isEmpty && activeOutputLayout == nil && voiceCleanup == .disabled
        }
    }

    struct AnalysisSnapshot: Codable, Equatable {
        let cursorTrackPath: String?
        let silenceAnalysisPath: String?

        static let empty = AnalysisSnapshot(cursorTrackPath: nil, silenceAnalysisPath: nil)

        init(cursorTrackPath: String?, silenceAnalysisPath: String?) {
            self.cursorTrackPath = cursorTrackPath
            self.silenceAnalysisPath = silenceAnalysisPath
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            cursorTrackPath = try container.decodeIfPresent(String.self, forKey: .cursorTrackPath)
            silenceAnalysisPath = try container.decodeIfPresent(String.self, forKey: .silenceAnalysisPath)
        }

        var isEmpty: Bool {
            cursorTrackPath == nil && silenceAnalysisPath == nil
        }
    }

    struct EditorStateSnapshot: Codable, Equatable {
        let hiddenVideoSources: [String]
        let mutedAudioSources: [String]
        let backgroundMusicPath: String?
        let backgroundMusicBookmarkData: Data?
        let backgroundMusicVolume: Double?
        let exportRecipe: ExportRecipeSnapshot?

        static let empty = EditorStateSnapshot(
            hiddenVideoSources: [],
            mutedAudioSources: [],
            backgroundMusicPath: nil,
            backgroundMusicBookmarkData: nil,
            backgroundMusicVolume: nil,
            exportRecipe: nil
        )
    }
}

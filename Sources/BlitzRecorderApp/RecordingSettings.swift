import BlitzRecorderCore
import CoreGraphics
import CoreMedia
import Foundation

struct RecordingStorageLocation: Codable, Equatable {
    let url: URL
    let bookmarkData: Data?
}

struct RecordingSettings {
    var voiceCleanup: VoiceCleanupSettings = .disabled
    static let supportedFrameRates = [24, 30, 60]
    static let minExportVideoBitrate = 400_000
    static let minCustomVideoBitrate = 2_000_000
    static let maxCustomVideoBitrate = 80_000_000

    var layout: CaptureLayout = .vertical
    var outputResolution: OutputResolution = .p1080
    var outputVideoFormat: OutputVideoFormat = .mov
    var framesPerSecond: Int = 30
    var customVideoBitrate: Int?
    var exportEncoding: ExportEncodingProfile?
    var audioQuality: AudioQuality = .standard
    var sourceAudioFormat: SourceAudioFormat = .aac
    var microphoneGain: Double = 1.0
    var systemAudioGain: Double = 1.0
    var removesCameraBackgroundAfterRecording: Bool = false
    var savesSourceFiles: Bool = true
    var showsRuleOfThirdsOverlay: Bool = false
    var socialSafeZoneOverlay: SocialVideoSafeZone = .none
    var includeCursor: Bool = true
    var enabledSources: Set<CaptureSource> = [.screen, .camera, .microphone]
    var hiddenSources: Set<CaptureSource> = []
    var usesPickedScreenContent: Bool = false
    var screenSourceBinding: ScreenSourceBinding? = .display(id: nil)
    var selectedDisplayID: String?
    var selectedCameraID: String?
    var selectedMicrophoneID: String?
    var trustedRemoteCameraServiceIDs: Set<String> = []
    var remoteCameraSettingsByServiceID: [String: RemoteCameraSettings] = [:]
    var screenCrop: CGRect?
    var screenSourceAspectRatio: CGFloat?
    var screenWindowZoom: CGFloat = 1
    var cameraCropAmount: CGPoint = .zero
    var cameraCropPosition: CGPoint = .zero
    var canvasBackgroundStyle: CanvasBackgroundStyle = .black
    var canvasBackgroundAnimated: Bool = false
    var canvasPadding: CGFloat = 0
    var screenCornerRadius: CGFloat = 0
    var screenShadowEnabled: Bool = false
    var screenContentMode: CameraContentMode = .fill
    var cameraContentMode: CameraContentMode = .fill
    var cameraFramePadding: CGFloat = 0
    var cameraShadowEnabled: Bool = false
    var sceneLayout = SceneLayout()
    var selectedScenePreset: ScenePreset?
    var projectLibrary: RecordingStorageLocation?
    var additionalProjectLibraries: [RecordingStorageLocation] = []
    var outputDirectoryBookmarkData: Data?
    var outputDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Movies", isDirectory: true)
        .appendingPathComponent("BlitzRecorder", isDirectory: true)

    var sourceStorage: RecordingStorageLocation {
        projectLibrary ?? RecordingStorageLocation(url: outputDirectory, bookmarkData: outputDirectoryBookmarkData)
    }

    var projectLibraries: [RecordingStorageLocation] {
        var seen: Set<URL> = []
        return ([sourceStorage] + additionalProjectLibraries).filter {
            seen.insert($0.url.standardizedFileURL.resolvingSymlinksInPath()).inserted
        }
    }

    var autoVideoBitrate: Int {
        SocialVideoEncoding.videoBitrate(
            resolution: outputResolution,
            fps: framesPerSecond
        )
    }

    var screenBitrate: Int {
        let base = SocialVideoEncoding.screenIntermediateBitrate(
            resolution: outputResolution,
            layout: layout,
            fps: framesPerSecond
        )
        return Int(Double(base) * intermediateVideoBoost)
    }

    var cameraBitrate: Int {
        let base = SocialVideoEncoding.cameraIntermediateBitrate(
            resolution: outputResolution,
            fps: framesPerSecond
        )
        return Int(Double(base) * intermediateVideoBoost)
    }

    var finalVideoBitrate: Int {
        if let exportEncoding {
            return exportEncoding.bitrate
        }
        guard let customVideoBitrate else { return autoVideoBitrate }
        return min(
            RecordingSettings.maxCustomVideoBitrate,
            max(RecordingSettings.minCustomVideoBitrate, customVideoBitrate)
        )
    }

    var finalAudioBitrate: Int {
        exportEncoding?.audioBitrate ?? audioQuality.bitrate
    }

    var effectiveSourceAudioFormat: SourceAudioFormat {
        savesSourceFiles ? sourceAudioFormat : .aac
    }

    var sourceVideoFormat: OutputVideoFormat {
        savesSourceFiles ? .mov : outputVideoFormat
    }

    private var intermediateVideoBoost: Double {
        guard customVideoBitrate != nil else { return 1.0 }
        let boost = Double(finalVideoBitrate) / Double(autoVideoBitrate)
        return min(2.5, max(0.5, boost))
    }

    var visibleSources: Set<CaptureSource> {
        enabledSources.subtracting(hiddenSources)
    }
}

struct RecordingTake {
    let scratchDirectory: URL
    let screenURL: URL
    let cameraURL: URL
    let audioURL: URL
    let systemAudioURL: URL
    let transcriptURL: URL
    let finalVideoURL: URL
    let outputVideoFormat: OutputVideoFormat
    let titleSlug: String?
    var timelineTrimOffset: CMTime = .zero
    var sourceTimelineOffsets: [CaptureSource: CMTime] = [:]
    var sourceReferences: [RecordingProject.SourceFile] = []

    var sourceManifestURL: URL {
        scratchDirectory.appendingPathComponent("take.json")
    }

    var projectURL: URL {
        scratchDirectory.appendingPathComponent("project.blitzrecorder.json")
    }
}

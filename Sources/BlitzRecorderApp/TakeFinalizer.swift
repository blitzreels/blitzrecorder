import Foundation

enum TakeFinalizationOutcome {
    case saved(URL, sourceDirectory: URL?)
    case recoveryFiles(RecordingTake, reason: String)

    var userMessage: String {
        switch self {
        case .saved(let url, let sourceDirectory):
            if let sourceDirectory {
                return "Saved: \(url.path). Source take: \(sourceDirectory.path)"
            }
            return "Saved: \(url.path)"
        case .recoveryFiles(let take, let reason):
            return "\(reason), recovery files: \(take.scratchDirectory.path)"
        }
    }
}

@MainActor
final class TakeFinalizer {
    var onMessage: ((String) -> Void)?
    var onRenderProgress: ((Double) -> Void)?

    private let speechTranscriber: SpeechTranscriber
    private let titleGenerator: TitleGenerator
    private let fileStore: TakeFileStore

    init(
        speechTranscriber: SpeechTranscriber,
        titleGenerator: TitleGenerator,
        fileStore: TakeFileStore = TakeFileStore()
    ) {
        self.speechTranscriber = speechTranscriber
        self.titleGenerator = titleGenerator
        self.fileStore = fileStore
    }

    func finalize(
        take: RecordingTake,
        settings: RecordingSettings,
        captureSummary: CaptureSourceRunSummary,
        sceneEvents: [RecordingSceneEvent] = []
    ) async -> TakeFinalizationOutcome {
        let renamedTake = await renameFromTranscriptIfPossible(take: take, settings: settings)
        let processedTake = await removeCameraBackgroundIfNeeded(from: renamedTake, settings: settings)

        if shouldSaveTransparentCameraOnly(take: processedTake, settings: settings) {
            do {
                let url = try saveTransparentCameraOnly(take: processedTake, settings: settings)
                onRenderProgress?(1)
                return try savedOutcome(url: url, take: processedTake, settings: settings)
            } catch {
                return .recoveryFiles(processedTake, reason: "Transparent webcam save failed: \(error.recorderFailureDescription)")
            }
        }

        guard captureSummary.hasVideoMedia else {
            onRenderProgress?(0)
            return .recoveryFiles(processedTake, reason: "No video frames captured")
        }

        do {
            onMessage?("Exporting final video...")
            onRenderProgress?(0)
            let url = try await Merger.exportFinalVideo(
                take: processedTake,
                settings: settings,
                sceneEvents: sceneEvents,
                progressHandler: { [weak self] progress in
                    self?.onRenderProgress?(progress)
                }
            )
            onRenderProgress?(1)
            return try savedOutcome(url: url, take: processedTake, settings: settings)
        } catch {
            onMessage?("Final video export skipped: \(error.recorderFailureDescription)")
            return .recoveryFiles(processedTake, reason: "Export failed: \(error.recorderFailureDescription)")
        }
    }

    private func savedOutcome(url: URL, take: RecordingTake, settings: RecordingSettings) throws -> TakeFinalizationOutcome {
        guard settings.savesSourceFiles else {
            fileStore.cleanupIntermediateFiles(for: take, settings: settings)
            return .saved(url, sourceDirectory: nil)
        }

        try fileStore.writeSourceTakeManifest(
            for: take,
            settings: settings,
            finalVideoURL: url
        )
        return .saved(url, sourceDirectory: take.scratchDirectory)
    }

    private func renameFromTranscriptIfPossible(take: RecordingTake, settings: RecordingSettings) async -> RecordingTake {
        guard settings.enabledSources.contains(.microphone),
              FileManager.default.fileExists(atPath: take.audioURL.path) else {
            return take
        }

        do {
            onMessage?("Transcribing audio...")
            let transcript = try await speechTranscriber.transcribe(audioURL: take.audioURL)
            let slug = await titleGenerator.titleSlug(for: transcript)
            let renamedTake = try rename(take: take, slug: slug, transcript: transcript, settings: settings)
            onMessage?("Renamed: \(slug)")
            return renamedTake
        } catch {
            onMessage?("Rename skipped: \(error.recorderFailureDescription)")
            return take
        }
    }

    private func removeCameraBackgroundIfNeeded(from take: RecordingTake, settings: RecordingSettings) async -> RecordingTake {
        guard settings.removesCameraBackgroundAfterRecording,
              settings.enabledSources.contains(.camera),
              FileManager.default.fileExists(atPath: take.cameraURL.path) else {
            return take
        }

        do {
            onMessage?("Removing webcam background...")
            onRenderProgress?(0)
            let baseName = take.cameraURL.deletingPathExtension().lastPathComponent
            let processedURL = take.cameraURL
                .deletingLastPathComponent()
                .appendingPathComponent("\(baseName)-background-removed.mov")
            let outputURL = try await CameraBackgroundPostProcessor.removeBackground(
                from: take.cameraURL,
                to: processedURL,
                progressHandler: { [weak self] progress in
                    self?.onRenderProgress?(progress)
                }
            )
            onRenderProgress?(1)
            return replaceCameraURL(in: take, with: outputURL)
        } catch {
            onMessage?("Webcam background removal skipped: \(error.recorderFailureDescription)")
            onRenderProgress?(0)
            return take
        }
    }

    private func shouldSaveTransparentCameraOnly(take: RecordingTake, settings: RecordingSettings) -> Bool {
        settings.removesCameraBackgroundAfterRecording
            && settings.enabledSources.contains(.camera)
            && !settings.enabledSources.contains(.screen)
            && !hasEnabledAudioSource(settings)
            && FileManager.default.fileExists(atPath: take.cameraURL.path)
            && take.cameraURL.pathExtension.lowercased() == "mov"
    }

    private func hasEnabledAudioSource(_ settings: RecordingSettings) -> Bool {
        settings.enabledSources.contains(.microphone)
            || settings.enabledSources.contains(.systemAudio)
    }

    private func saveTransparentCameraOnly(take: RecordingTake, settings: RecordingSettings) throws -> URL {
        onMessage?("Saving transparent webcam video...")
        try FileManager.default.createDirectory(
            at: settings.outputDirectory,
            withIntermediateDirectories: true
        )
        let baseName = take.titleSlug ?? "recording"
        let outputURL = fileStore.uniqueFileURL(
            settings.outputDirectory.appendingPathComponent("\(baseName)-transparent-webcam.mov")
        )
        try FileManager.default.copyItem(at: take.cameraURL, to: outputURL)
        return outputURL
    }

    private func rename(take: RecordingTake, slug: String, transcript: String, settings: RecordingSettings) throws -> RecordingTake {
        let datedSlug = fileStore.datedSlug(for: take, slug: slug)
        let fileManager = FileManager.default
        let parentDirectory = take.scratchDirectory.deletingLastPathComponent()
        let renamedDirectory = uniqueDirectory(
            parentDirectory.appendingPathComponent(datedSlug, isDirectory: true)
        )

        try fileManager.moveItem(at: take.scratchDirectory, to: renamedDirectory)

        let currentScreenURL = renamedDirectory.appendingPathComponent(take.screenURL.lastPathComponent)
        let currentCameraURL = renamedDirectory.appendingPathComponent(take.cameraURL.lastPathComponent)
        let currentAudioURL = renamedDirectory.appendingPathComponent(take.audioURL.lastPathComponent)
        let currentSystemAudioURL = renamedDirectory.appendingPathComponent(take.systemAudioURL.lastPathComponent)

        let renamedScreenURL = renamedDirectory.appendingPathComponent("\(datedSlug)-screen.\(take.outputVideoFormat.fileExtension)")
        let renamedCameraURL = renamedDirectory.appendingPathComponent("\(datedSlug)-camera.\(take.outputVideoFormat.fileExtension)")
        let renamedAudioURL = renamedDirectory.appendingPathComponent("\(datedSlug)-audio.m4a")
        let renamedSystemAudioURL = renamedDirectory.appendingPathComponent("\(datedSlug)-system-audio.m4a")
        let renamedTranscriptURL = renamedDirectory.appendingPathComponent("\(datedSlug)-transcript.txt")

        try moveIfPresent(from: currentScreenURL, to: renamedScreenURL)
        try moveIfPresent(from: currentCameraURL, to: renamedCameraURL)
        try moveIfPresent(from: currentAudioURL, to: renamedAudioURL)
        try moveIfPresent(from: currentSystemAudioURL, to: renamedSystemAudioURL)
        try transcript.write(to: renamedTranscriptURL, atomically: true, encoding: .utf8)

        return RecordingTake(
            scratchDirectory: renamedDirectory,
            screenURL: renamedScreenURL,
            cameraURL: renamedCameraURL,
            audioURL: renamedAudioURL,
            systemAudioURL: renamedSystemAudioURL,
            transcriptURL: renamedTranscriptURL,
            finalVideoURL: fileStore.finalVideoURL(slug: datedSlug, settings: settings, outputFormat: take.outputVideoFormat),
            outputVideoFormat: take.outputVideoFormat,
            titleSlug: datedSlug
        )
    }

    private func replaceCameraURL(in take: RecordingTake, with cameraURL: URL) -> RecordingTake {
        RecordingTake(
            scratchDirectory: take.scratchDirectory,
            screenURL: take.screenURL,
            cameraURL: cameraURL,
            audioURL: take.audioURL,
            systemAudioURL: take.systemAudioURL,
            transcriptURL: take.transcriptURL,
            finalVideoURL: take.finalVideoURL,
            outputVideoFormat: take.outputVideoFormat,
            titleSlug: take.titleSlug
        )
    }

    private func moveIfPresent(from source: URL, to destination: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: source, to: destination)
    }

    private func uniqueDirectory(_ url: URL) -> URL {
        var candidate = url
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = url.deletingLastPathComponent()
                .appendingPathComponent("\(url.lastPathComponent)-\(index)", isDirectory: true)
            index += 1
        }
        return candidate
    }
}

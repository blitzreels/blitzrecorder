import Foundation

struct SavedRecordingOutput: Equatable {
    let url: URL
    let sourceDirectory: URL?
    let warning: String?

    var userMessage: String {
        let savedMessage: String
        if let sourceDirectory {
            savedMessage = "Saved: \(url.path). Source take: \(sourceDirectory.path)"
        } else {
            savedMessage = "Saved: \(url.path)"
        }

        guard let warning, !warning.isEmpty else { return savedMessage }
        return "\(warning). \(savedMessage)"
    }
}

struct RecordingRecoveryOutput: Equatable {
    let takeDirectory: URL
    let reason: String
    let canRetryExport: Bool

    var userMessage: String {
        "\(reason). Recovery files: \(takeDirectory.path)"
    }
}

struct PostRecordingProjectOutput: Equatable {
    let projectURL: URL
    let sourceDirectory: URL
    let warning: String?

    var userMessage: String {
        let message = "Project ready: \(projectURL.path). Source take: \(sourceDirectory.path)"
        guard let warning, !warning.isEmpty else { return message }
        return "\(warning). \(message)"
    }
}

enum TakeFinalizationOutcome {
    case projectReady(RecordingTake)
    case projectReadyWithWarning(RecordingTake, warning: String)
    case saved(URL, sourceDirectory: URL?)
    case recoveryFiles(RecordingTake, reason: String)

    var userMessage: String {
        switch self {
        case .projectReady(let take):
            return "Project ready: \(take.projectURL.path). Source take: \(take.scratchDirectory.path)"
        case .projectReadyWithWarning(let take, let warning):
            return "\(warning). Project ready: \(take.projectURL.path). Source take: \(take.scratchDirectory.path)"
        case .saved(let url, let sourceDirectory):
            if let sourceDirectory {
                return "Saved: \(url.path). Source take: \(sourceDirectory.path)"
            }
            return "Saved: \(url.path)"
        case .recoveryFiles(let take, let reason):
            return "\(reason), recovery files: \(take.scratchDirectory.path)"
        }
    }

    func projectOutput(warning: String? = nil) -> PostRecordingProjectOutput? {
        let take: RecordingTake
        let outcomeWarning: String?
        switch self {
        case .projectReady(let projectTake):
            take = projectTake
            outcomeWarning = nil
        case .projectReadyWithWarning(let projectTake, let projectWarning):
            take = projectTake
            outcomeWarning = projectWarning
        default:
            return nil
        }
        return PostRecordingProjectOutput(
            projectURL: take.projectURL,
            sourceDirectory: take.scratchDirectory,
            warning: Self.combinedWarning(warning, outcomeWarning)
        )
    }

    func savedOutput(warning: String? = nil) -> SavedRecordingOutput? {
        guard case .saved(let url, let sourceDirectory) = self else { return nil }
        return SavedRecordingOutput(url: url, sourceDirectory: sourceDirectory, warning: warning)
    }

    func recoveryOutput(reason overrideReason: String? = nil, canRetryExport: Bool = true) -> RecordingRecoveryOutput? {
        guard case .recoveryFiles(let take, let reason) = self else { return nil }
        return RecordingRecoveryOutput(
            takeDirectory: take.scratchDirectory,
            reason: overrideReason ?? reason,
            canRetryExport: canRetryExport
        )
    }

    private static func combinedWarning(_ first: String?, _ second: String?) -> String? {
        let warning = [first, second]
            .compactMap { warning in
                guard let warning, !warning.isEmpty else { return nil }
                return warning
            }
            .joined(separator: ". ")
        return warning.isEmpty ? nil : warning
    }
}

@MainActor
final class TakeFinalizer {
    var onMessage: ((String) -> Void)?
    var onRenderProgress: ((Double) -> Void)?

    private let fileStore = TakeFileStore()

    func finalize(
        take: RecordingTake,
        settings: RecordingSettings,
        captureSummary: CaptureSourceRunSummary,
        sceneEvents: [RecordingSceneEvent] = []
    ) async -> TakeFinalizationOutcome {
        let finalizationSettings = settingsForFinalization(settings, captureSummary: captureSummary)
        var synchronizedTake = take
        synchronizedTake.timelineTrimOffset = captureSummary.timelineTrimOffset
        synchronizedTake.sourceTimelineOffsets = captureSummary.sourceTimelineOffsets
        let processedTake = await removeCameraBackgroundIfNeeded(from: synchronizedTake, settings: finalizationSettings)
        let plan = TakeFinalizationPlan(
            take: processedTake,
            settings: finalizationSettings,
            captureSummary: captureSummary,
            sceneEvents: sceneEvents
        )

        switch plan.action {
        case .saveTransparentCameraOnly:
            do {
                let url = try saveTransparentCameraOnly(take: processedTake, settings: finalizationSettings)
                onRenderProgress?(1)
                return try savedOutcome(
                    url: url,
                    take: processedTake,
                    settings: finalizationSettings,
                    sceneEvents: sceneEvents
                )
            } catch {
                try? writeRecoverableProject(
                    take: processedTake,
                    settings: finalizationSettings,
                    sceneEvents: sceneEvents
                )
                return .recoveryFiles(processedTake, reason: "Transparent camera save failed: \(error.recorderFailureDescription)")
            }
        case .recoverNoVideo(let reason):
            onRenderProgress?(0)
            try? writeRecoverableProject(
                take: processedTake,
                settings: finalizationSettings,
                sceneEvents: sceneEvents
            )
            return .recoveryFiles(processedTake, reason: reason)
        case .exportFinalVideo:
            let missingAudioSources = missingRequiredAudioSources(
                settings: finalizationSettings,
                captureSummary: captureSummary
            )
            if !missingAudioSources.isEmpty {
                let audioReason = missingRequiredAudioReason(for: missingAudioSources)
                if finalizationSettings.savesSourceFiles {
                    var projectSettings = finalizationSettings
                    projectSettings.enabledSources.subtract(missingAudioSources)
                    return projectReadyOutcome(
                        take: processedTake,
                        settings: projectSettings,
                        sceneEvents: sceneEvents,
                        warning: "\(audioReason). Project is editable without that audio"
                    )
                }
                try? writeRecoverableProject(
                    take: processedTake,
                    settings: finalizationSettings,
                    sceneEvents: sceneEvents
                )
                return .recoveryFiles(processedTake, reason: audioReason)
            }
            if finalizationSettings.savesSourceFiles {
                return projectReadyOutcome(
                    take: processedTake,
                    settings: finalizationSettings,
                    sceneEvents: sceneEvents
                )
            }
            return await exportFinalVideo(
                take: processedTake,
                settings: finalizationSettings,
                sceneEvents: sceneEvents
            )
        }
    }

    private func projectReadyOutcome(
        take: RecordingTake,
        settings: RecordingSettings,
        sceneEvents: [RecordingSceneEvent],
        warning: String? = nil
    ) -> TakeFinalizationOutcome {
        do {
            onMessage?("Preparing editable project...")
            onRenderProgress?(1)
            try writeRecoverableProject(
                take: take,
                settings: settings,
                sceneEvents: sceneEvents
            )
            if let warning, !warning.isEmpty {
                return .projectReadyWithWarning(take, warning: warning)
            }
            return .projectReady(take)
        } catch {
            return .recoveryFiles(take, reason: "Project save failed: \(error.recorderFailureDescription)")
        }
    }

    private func settingsForFinalization(
        _ settings: RecordingSettings,
        captureSummary: CaptureSourceRunSummary
    ) -> RecordingSettings {
        var settings = settings
        for source in [CaptureSource.microphone, .systemAudio] where captureSummary.stopFailures[source] != nil {
            if captureSummary.completions[source]?.wroteMedia != true {
                settings.enabledSources.remove(source)
            }
        }
        if captureSummary.completions[.systemAudio]?.wroteMedia == false {
            settings.enabledSources.remove(.systemAudio)
        }
        return settings
    }

    private func missingRequiredAudioSources(
        settings: RecordingSettings,
        captureSummary: CaptureSourceRunSummary
    ) -> Set<CaptureSource> {
        Set([CaptureSource.microphone, .systemAudio].filter { source in
            settings.enabledSources.contains(source)
                && captureSummary.completions[source]?.wroteMedia != true
        })
    }

    private func missingRequiredAudioReason(for missingSources: Set<CaptureSource>) -> String {
        let names = missingSources.map(\.rawValue).sorted().joined(separator: " and ")
        return "\(names) audio could not be finalized"
    }

    private func exportFinalVideo(
        take: RecordingTake,
        settings: RecordingSettings,
        sceneEvents: [RecordingSceneEvent]
    ) async -> TakeFinalizationOutcome {
        do {
            onMessage?("Exporting final video...")
            onRenderProgress?(0)
            let url = try await Merger.exportFinalVideo(
                take: take,
                settings: settings,
                sceneEvents: sceneEvents,
                progressHandler: { [weak self] progress in
                    self?.onRenderProgress?(progress)
                }
            )
            onRenderProgress?(1)
            return try savedOutcome(
                url: url,
                take: take,
                settings: settings,
                sceneEvents: sceneEvents
            )
        } catch {
            onMessage?("Final video export skipped: \(error.recorderFailureDescription)")
            try? writeRecoverableProject(take: take, settings: settings, sceneEvents: sceneEvents)
            return .recoveryFiles(take, reason: "Export failed: \(error.recorderFailureDescription)")
        }
    }

    private func savedOutcome(
        url: URL,
        take: RecordingTake,
        settings: RecordingSettings,
        sceneEvents: [RecordingSceneEvent]
    ) throws -> TakeFinalizationOutcome {
        guard settings.savesSourceFiles else {
            fileStore.cleanupIntermediateFiles(for: take, settings: settings)
            return .saved(url, sourceDirectory: nil)
        }

        try fileStore.writeSourceTakeManifest(
            for: take,
            settings: settings,
            finalVideoURL: url
        )
        try fileStore.writeRecordingProject(
            for: take,
            settings: settings,
            sceneEvents: sceneEvents,
            finalVideoURL: url
        )
        return .saved(url, sourceDirectory: take.scratchDirectory)
    }

    private func writeRecoverableProject(
        take: RecordingTake,
        settings: RecordingSettings,
        sceneEvents: [RecordingSceneEvent]
    ) throws {
        guard settings.savesSourceFiles else { return }
        try fileStore.writeSourceTakeManifest(
            for: take,
            settings: settings,
            finalVideoURL: nil
        )
        try fileStore.writeRecordingProject(
            for: take,
            settings: settings,
            sceneEvents: sceneEvents,
            finalVideoURL: nil
        )
    }

    private func removeCameraBackgroundIfNeeded(from take: RecordingTake, settings: RecordingSettings) async -> RecordingTake {
        guard settings.removesCameraBackgroundAfterRecording,
              settings.enabledSources.contains(.camera),
              FileManager.default.fileExists(atPath: take.cameraURL.path) else {
            return take
        }

        do {
            onMessage?("Removing camera background...")
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
            onMessage?("Camera background removal skipped: \(error.recorderFailureDescription)")
            onRenderProgress?(0)
            return take
        }
    }

    private func saveTransparentCameraOnly(take: RecordingTake, settings: RecordingSettings) throws -> URL {
        onMessage?("Saving transparent camera video...")
        try FileManager.default.createDirectory(
            at: settings.outputDirectory,
            withIntermediateDirectories: true
        )
        let baseName = take.titleSlug ?? fileStore.defaultSlug(for: take)
        let outputURL = fileStore.uniqueFileURL(
            settings.outputDirectory.appendingPathComponent("\(baseName)-transparent-webcam.mov")
        )
        try FileManager.default.copyItem(at: take.cameraURL, to: outputURL)
        return outputURL
    }

    private func replaceCameraURL(in take: RecordingTake, with cameraURL: URL) -> RecordingTake {
        var updatedTake = RecordingTake(
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
        updatedTake.timelineTrimOffset = take.timelineTrimOffset
        updatedTake.sourceTimelineOffsets = take.sourceTimelineOffsets
        return updatedTake
    }

}

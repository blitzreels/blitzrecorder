import SwiftUI

extension ProjectLibraryView {
    struct TranscriptUnavailableRequest {
        let project: RecordingProjectHistory.Entry
        let status: TranscriptionJobStatus
    }

    @ViewBuilder
    func transcriptUnavailableState(
        _ request: TranscriptUnavailableRequest
    ) -> some View {
        if request.status == .waitingForModel {
            transcriptionModelState(request.project)
        } else {
            transcriptJobState(request)
        }
    }

    private func transcriptJobState(
        _ request: TranscriptUnavailableRequest
    ) -> some View {
        HStack(spacing: 12) {
            if request.status.isRunning {
                ProgressView()
                    .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(transcriptStatusLabel(request.status))
                    .font(BlitzType.strong)
                    .foregroundStyle(BlitzUI.supportingText)
                Text(vm.transcriptionController.jobDetails[request.project.projectPath]
                     ?? transcriptUnavailableDetail(request.status))
                    .font(BlitzType.footnote)
                    .foregroundStyle(BlitzUI.tertiaryText)
            }

            Spacer(minLength: 0)

            if let startedAt = vm.transcriptionController.jobStartedAt[request.project.projectPath] {
                ActivityElapsedTime(startedAt: startedAt)
            }
            if !request.status.isRunning, request.status != .noAudio {
                Button(transcriptActionTitle(request.status)) {
                    performTranscriptAction(request.project)
                }
                .buttonStyle(BlitzButtonStyle(.secondary))
                .pointingHandCursor()
            }
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func transcriptionModelState(
        _ project: RecordingProjectHistory.Entry
    ) -> some View {
        switch vm.transcriptionController.modelState {
        case .notDownloaded:
            transcriptionModelCard(.init(
                title: "Local speech model required",
                detail: "Download it once to generate timed transcripts and detect speakers on this Mac.",
                systemImage: "arrow.down.circle",
                errorMessage: nil,
                progress: nil,
                progressLabel: nil,
                actionTitle: "Download and Generate",
                action: { requestTranscript(project) }
            ))
        case .downloading(let progress, let phase):
            transcriptionModelCard(.init(
                title: "Downloading speech model",
                detail: "Keep BlitzRecorder open. Transcription starts when the model is ready.",
                systemImage: "arrow.down.circle.fill",
                errorMessage: nil,
                progress: progress,
                progressLabel: "\(phase) · \(Int((progress * 100).rounded()))%",
                actionTitle: nil,
                action: nil
            ))
        case .failed(let message):
            transcriptionModelCard(.init(
                title: "Model download failed",
                detail: "The model is stored locally and can be downloaded again.",
                systemImage: "exclamationmark.triangle.fill",
                errorMessage: message,
                progress: nil,
                progressLabel: nil,
                actionTitle: "Retry Download",
                action: { requestTranscript(project) }
            ))
        case .ready:
            transcriptJobState(TranscriptUnavailableRequest(
                project: project,
                status: .queued
            ))
        }
    }

    private struct TranscriptionModelCardConfiguration {
        let title: String
        let detail: String
        let systemImage: String
        let errorMessage: String?
        let progress: Double?
        let progressLabel: String?
        let actionTitle: String?
        let action: (() -> Void)?
    }

    private func transcriptionModelCard(
        _ configuration: TranscriptionModelCardConfiguration
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: configuration.systemImage)
                .font(BlitzType.glyph(19))
                .foregroundStyle(
                    configuration.errorMessage == nil
                        ? BlitzUI.mint
                        : BlitzUI.warning
                )
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 7) {
                Text(configuration.title)
                    .font(BlitzType.strong)
                    .foregroundStyle(BlitzUI.supportingText)

                Text(configuration.detail)
                    .font(BlitzType.footnote)
                    .foregroundStyle(BlitzUI.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let progress = configuration.progress {
                    ProgressView(value: progress)
                        .tint(BlitzUI.mint)
                        .frame(maxWidth: 360)
                }

                if let progressLabel = configuration.progressLabel {
                    Text(progressLabel)
                        .font(BlitzType.footnote.monospaced())
                        .monospacedDigit()
                        .foregroundStyle(BlitzUI.secondaryText)
                }

                if let errorMessage = configuration.errorMessage {
                    Text(errorMessage)
                        .font(BlitzType.footnote)
                        .foregroundStyle(BlitzUI.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            if let actionTitle = configuration.actionTitle,
               let action = configuration.action {
                Button(actionTitle, action: action)
                    .buttonStyle(BlitzButtonStyle(.secondary))
                    .pointingHandCursor()
            }
        }
        .padding(.vertical, 12)
    }

    private func performTranscriptAction(
        _ project: RecordingProjectHistory.Entry
    ) {
        switch vm.transcriptionController.status(for: project) {
        case .ready:
            Task { await loadSelectedTranscript() }
        case .notGenerated, .failed:
            vm.transcriptionController.retry(.project(
                URL(fileURLWithPath: project.projectPath)
            ))
        case .waitingForModel:
            requestTranscript(project)
        case .noAudio, .queued, .preparingAudio, .loadingModels, .transcribing, .diarizing, .saving:
            break
        }
    }

    func requestTranscript(
        _ project: RecordingProjectHistory.Entry
    ) {
        vm.transcriptionController.retry(.project(
            URL(fileURLWithPath: project.projectPath)
        ))
    }

    private func transcriptActionTitle(
        _ status: TranscriptionJobStatus
    ) -> String {
        switch status {
        case .ready:
            return "Reload Transcript"
        case .failed:
            return "Retry Transcript"
        case .notGenerated:
            return "Generate Transcript"
        case .noAudio:
            return "No audio track"
        case .waitingForModel:
            return "Download Model"
        case .queued, .preparingAudio, .loadingModels, .transcribing, .diarizing, .saving:
            return status.label
        }
    }

    func transcriptStatusLabel(
        _ status: TranscriptionJobStatus
    ) -> String {
        switch status {
        case .ready:
            return "Transcript ready"
        case .failed:
            return "Transcript failed"
        case .waitingForModel:
            return "Speech model required"
        case .notGenerated:
            return "No transcript"
        case .noAudio:
            return "No audio track"
        case .queued, .preparingAudio, .loadingModels, .transcribing, .diarizing, .saving:
            return status.label
        }
    }

    func transcriptStatusColor(
        _ status: TranscriptionJobStatus
    ) -> Color {
        switch status {
        case .ready:
            return BlitzUI.mint.opacity(0.84)
        case .failed:
            return BlitzUI.warning
        case .notGenerated, .noAudio, .waitingForModel,
             .queued, .preparingAudio, .loadingModels, .transcribing, .diarizing, .saving:
            return BlitzUI.tertiaryText
        }
    }

    private func transcriptUnavailableDetail(
        _ status: TranscriptionJobStatus
    ) -> String {
        switch status {
        case .ready:
            return "The saved transcript could not be loaded."
        case .failed:
            return "Retry local transcription for this recording."
        case .waitingForModel:
            return "Download the local speech model to find speakers and segments."
        case .notGenerated:
            return "Generate timed text and speaker diarization locally."
        case .noAudio:
            return "This video has no audio track. You can still edit and export it."
        case .queued:
            return "Waiting for local transcription to start."
        case .preparingAudio:
            return "Preparing the project audio."
        case .loadingModels:
            return "Loading the speech model into memory."
        case .transcribing:
            return "Converting speech into timed text."
        case .diarizing:
            return "Finding and separating speakers."
        case .saving:
            return "Saving the inline transcript."
        }
    }

}

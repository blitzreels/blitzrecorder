import SwiftUI

extension ProjectLibraryView {
    private func speakerColor(_ index: Int) -> Color {
        let colors: [Color] = [
            BlitzUI.mint,
            .blue,
            .purple,
            .orange,
            .pink,
            .teal,
        ]
        return colors[index % colors.count]
    }

    private struct TranscriptRowRequest {
        let segment: RecordingTranscript.Segment
        let transcript: RecordingTranscript
        let showsSpeaker: Bool
    }

    func transcriptHeader(
        _ project: RecordingProjectHistory.Entry
    ) -> some View {
        let status = vm.transcriptionController.status(for: project)
        return HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Transcript").font(BlitzType.section).foregroundStyle(BlitzUI.primaryText)
                Text(vm.transcriptionController.speakerFixDetails[project.projectPath]
                     ?? selectedTranscript.map(transcriptSummaryLabel)
                     ?? transcriptStatusLabel(status))
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if status.isRunning || status == .waitingForModel {
                TranscriptionActivityView(configuration: .init(
                    status: status,
                    detail: vm.transcriptionController.jobDetails[project.projectPath],
                    startedAt: vm.transcriptionController.jobStartedAt[project.projectPath]
                ))
            } else if let transcript = selectedTranscript {
                TranscriptCopyButton(.init(
                    markdown: transcript.markdownText(title: displayTitle(project)),
                    appearance: .compact
                ))
                BlitzGlassMenu(entries: transcriptMenuEntries(.init(project: project, transcript: transcript, status: status)),
                               menuWidth: 220) {
                    Group {
                        if titleGenerationProjectID == project.id
                            || vm.transcriptionController.isFixingSpeakers(project) {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "ellipsis").font(BlitzType.glyph(13))
                        }
                    }
                    .foregroundStyle(BlitzUI.primaryText)
                    .frame(width: 30, height: BlitzControlMetrics.height(.small))
                }
                .accessibilityLabel("Transcript actions")
                .help("Generate a title, fix speakers, or retranscribe")
            }
        }
    }

    private struct TranscriptMenuRequest {
        let project: RecordingProjectHistory.Entry
        let transcript: RecordingTranscript
        let status: TranscriptionJobStatus
    }

    private func transcriptMenuEntries(_ request: TranscriptMenuRequest) -> [BlitzMenuEntry] {
        [
            .item(.init(title: "Generate title", subtitle: "From the transcript, on this Mac", systemImage: "wand.and.stars",
                        isEnabled: titleGenerationProjectID == nil, action: {
                titleGenerationProjectID = request.project.id
                Task {
                    await vm.generateProjectTitle(ProjectTranscriptTitleRequest(
                        project: request.project, transcript: request.transcript.formattedText
                    ))
                    titleGenerationProjectID = nil
                }
            })),
            .item(.init(title: "Fix speakers", subtitle: "Find who is talking again, keep the words",
                        systemImage: "person.2.wave.2.fill",
                        isEnabled: vm.transcriptionController.canFixSpeakers(request.project)
                            && !(request.transcript.words ?? []).isEmpty,
                        action: { fixSpeakers(request.project) })),
            .item(.init(title: request.status.isFailed ? "Retry transcription" : "Retranscribe",
                        subtitle: "Create a new transcript from the audio", systemImage: "arrow.clockwise",
                        isEnabled: !vm.transcriptionController.isFixingSpeakers(request.project),
                        action: { requestTranscript(request.project) }))
        ]
    }

    private func renameSpeaker(_ request: ProjectTranscriptSpeakerRenameRequest) {
        Task {
            guard await vm.renameTranscriptSpeaker(request),
                  let transcript = transcriptByProjectID[request.project.id] else { return }
            transcriptByProjectID[request.project.id] = transcript.renamingSpeaker(request.rename)
        }
    }

    private func fixSpeakers(_ project: RecordingProjectHistory.Entry) {
        Task {
            guard await vm.fixProjectSpeakers(project) != nil,
                  selectedProject?.id == project.id else { return }
            await loadSelectedTranscript()
        }
    }

    @ViewBuilder
    func transcriptBody(
        _ project: RecordingProjectHistory.Entry
    ) -> some View {
        let status = vm.transcriptionController.status(for: project)
        if let transcript = selectedTranscript {
            let matches = transcriptMatches[project.id] ?? []
            let matchIDs = Set(matches.map(\.id))
            VStack(alignment: .leading, spacing: 8) {
                if !matches.isEmpty {
                    Text("\(matches.count) matching moments · Click a timestamp to play")
                        .font(BlitzType.body)
                        .foregroundStyle(BlitzUI.mint)
                }
                if transcript.segments.isEmpty {
                    Text(transcript.text).font(BlitzType.callout).textSelection(.enabled)
                }
                let segments = matches.isEmpty ? transcript.segments : transcript.segments.filter { matchIDs.contains($0.id) }
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                        inlineTranscriptRow(TranscriptRowRequest(
                            segment: segment,
                            transcript: transcript,
                            showsSpeaker: transcript.speakerCount > 1
                                && (index == 0 || segments[index - 1].speakerID != segment.speakerID)
                        ))
                    }
                }
            }
        } else if case .ready = status, !transcriptUnavailableIDs.contains(project.id) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(0..<6, id: \.self) { index in
                    HStack(alignment: .top, spacing: 18) {
                        RoundedRectangle(cornerRadius: 3).fill(BlitzUI.quietFill).frame(width: 34, height: 10)
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 3).fill(BlitzUI.controlFill).frame(height: 10)
                            RoundedRectangle(cornerRadius: 3).fill(BlitzUI.quietFill)
                                .frame(width: [180, 120, 220, 90, 160, 200][index], height: 10)
                        }
                    }
                }
            }
            .padding(.top, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading transcript")
        } else {
            transcriptUnavailableState(TranscriptUnavailableRequest(
                project: project,
                status: status
            ))
        }
    }

    private func inlineTranscriptRow(
        _ request: TranscriptRowRequest
    ) -> some View {
        let speakerIndex = request.transcript.speakers.firstIndex {
            $0.id == request.segment.speakerID
        } ?? 0
        return HStack(alignment: .top, spacing: 18) {
            TranscriptTimestampButton(
                timestamp: durationLabel(request.segment.startTime),
                isEnabled: playbackProjectID == selectedProject?.id && projectPlayback.isReady,
                isActive: projectPlayback.isPlaying
                    && projectPlayback.nowPlayingTime >= request.segment.startTime
                    && projectPlayback.nowPlayingTime < request.segment.endTime,
                action: {
                    projectPlayback.playFromOutput(request.segment.startTime)
                }
            )

            VStack(alignment: .leading, spacing: 6) {
                if request.showsSpeaker {
                    TranscriptSpeakerLabel(configuration: .init(
                        name: request.transcript.speakerName(for: request.segment.speakerID),
                        currentName: request.transcript.speakers
                            .first { $0.id == request.segment.speakerID }?.name ?? "",
                        color: speakerColor(speakerIndex),
                        onRename: { name in
                            guard let project = selectedProject else { return }
                            renameSpeaker(ProjectTranscriptSpeakerRenameRequest(
                                project: project,
                                rename: .init(speakerID: request.segment.speakerID, name: name)
                            ))
                        }
                    ))
                    .padding(.top, 2)
                }

                Text(request.segment.text)
                    .font(BlitzType.callout)
                    .foregroundStyle(BlitzUI.primaryText)
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, request.showsSpeaker ? 0 : 3)
            }
        }
        .padding(.top, request.showsSpeaker ? 18 : 6)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func transcriptSummaryLabel(
        _ transcript: RecordingTranscript
    ) -> String {
        if transcript.speakerCount == 1,
           let speaker = transcript.speakers.first {
            return "\(durationLabel(transcript.speakingDuration(for: speaker.id))) · "
                + "\(transcript.segmentCount) segments"
        }
        return "\(transcript.speakerCount) speakers · "
            + "\(transcript.segmentCount) segments"
    }

    private func durationLabel(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

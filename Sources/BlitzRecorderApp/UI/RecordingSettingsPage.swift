import SwiftUI

struct RecordingSettingsPage: View {
    @Bindable var vm: RecorderViewModel
    @State private var showsAdvancedEncoding = false

    private var canEdit: Bool {
        vm.state == .idle
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SettingsPageHeader(.init(
                    title: "General",
                    detail: "Storage, editable projects, and local transcription.",
                    systemImage: "gearshape",
                    status: nil
                ))
                .padding(.bottom, 4)

                storageSection
                transcriptionSection

                DisclosureGroup(isExpanded: $showsAdvancedEncoding) {
                    advancedSection
                        .padding(.top, 12)
                } label: {
                    Text("Advanced encoding")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BlitzUI.secondaryText)
                }
            }
            .settingsPageContent()
        }
        .background(BlitzUI.projectLibraryBackground)
        .foregroundStyle(.white)
    }

    private var storageSection: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 18) {
                SettingsRowLabel(.init(
                    title: "Save recordings to",
                    detail: vm.settings.outputDirectory.path
                ))

                Spacer(minLength: 16)

                Button("Choose…") {
                    vm.chooseOutputFolder()
                }
                .blitzGlassButton()
                .pointingHandCursor()
                .disabled(!canEdit)
            }
            .settingsRow()

            SettingsRowDivider()

            Toggle(
                isOn: Binding(
                    get: { vm.settings.savesSourceFiles },
                    set: { vm.setSourceFilesSaved($0) }
                )
            ) {
                SettingsRowLabel(.init(
                    title: "Keep editable projects",
                    detail: "Save separate screen, camera, microphone, and system-audio tracks."
                ))
            }
            .toggleStyle(.switch)
            .settingsRow()
            .disabled(!canEdit)
        }
        .settingsSection(.init(
            title: "Storage",
            detail: "Files stay on this Mac",
            systemImage: "internaldrive"
        ))
    }

    private var transcriptionSection: some View {
        VStack(spacing: 0) {
            Toggle(
                isOn: Binding(
                    get: {
                        vm.transcriptionController.isAutomaticEnabled
                    },
                    set: {
                        vm.transcriptionController.isAutomaticEnabled = $0
                    }
                )
            ) {
                SettingsRowLabel(.init(
                    title: "Automatic transcript and title",
                    detail: "Transcribe finished recordings and rename them from their content."
                ))
            }
            .toggleStyle(.switch)
            .settingsRow()

            SettingsRowDivider()

            HStack(alignment: .center, spacing: 18) {
                SettingsRowLabel(.init(
                    title: "Local speech model",
                    detail: transcriptionModelDetail
                ))

                Spacer(minLength: 16)

                transcriptionModelAction
            }
            .settingsRow()

            if case .downloading(let progress, let phase) = vm.transcriptionController.modelState {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: progress)
                        .tint(BlitzUI.mint)
                    Text(phase)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.44))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .settingsSection(.init(
            title: "Local transcription",
            detail: "Audio and model files never leave this Mac",
            systemImage: "waveform.badge.mic"
        ))
    }

    @ViewBuilder
    private var transcriptionModelAction: some View {
        switch vm.transcriptionController.modelState {
        case .notDownloaded, .failed:
            Button("Download model") {
                vm.transcriptionController.downloadModels()
            }
            .blitzGlassButton()
            .pointingHandCursor()
        case .downloading:
            Text("Downloading")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(BlitzUI.mint.opacity(0.72))
        case .ready:
            Button("Remove model") {
                vm.transcriptionController.removeModels()
            }
            .blitzGlassButton()
            .pointingHandCursor()
        }
    }

    private var advancedSection: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 18) {
                SettingsRowLabel(.init(
                    title: "Video detail override",
                    detail: qualityPresentation.bitrateOverrideDetail
                ))

                Spacer(minLength: 16)

                HStack(spacing: 10) {
                    Slider(
                        value: bitrateBinding,
                        in: Double(RecordingSettings.minCustomVideoBitrate / 1_000_000)
                            ... Double(RecordingSettings.maxCustomVideoBitrate / 1_000_000),
                        step: 1
                    )
                    .frame(width: 170)

                    Button(vm.settings.customVideoBitrate == nil ? "Custom" : "Auto") {
                        if vm.settings.customVideoBitrate == nil {
                            vm.setCustomVideoBitrate(vm.settings.autoVideoBitrate)
                        } else {
                            vm.setCustomVideoBitrate(nil)
                        }
                    }
                }
                .disabled(!canEdit)
            }

            SettingsRowDivider()

            HStack(alignment: .center, spacing: 18) {
                SettingsRowLabel(.init(
                    title: "Audio quality",
                    detail: vm.settings.audioQuality.plainDescription
                ))

                Spacer(minLength: 16)

                Picker("", selection: audioQualityBinding) {
                    ForEach(AudioQuality.allCases, id: \.self) { quality in
                        Text(quality.displayName)
                            .tag(quality)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
                .disabled(!canEdit)
            }

            if vm.settings.savesSourceFiles {
                SettingsRowDivider()

                HStack(alignment: .center, spacing: 18) {
                    SettingsRowLabel(.init(
                        title: "Source audio format",
                        detail: vm.settings.sourceAudioFormat.plainDescription
                    ))

                    Spacer(minLength: 16)

                    Picker("", selection: sourceAudioBinding) {
                        ForEach(SourceAudioFormat.allCases, id: \.self) { format in
                            Text(format.displayName)
                                .tag(format)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                    .disabled(!canEdit)
                }
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white.opacity(0.72))
        .settingsRow()

    }

    private var qualityPresentation: RecordingQualityPresentation {
        RecordingQualityPresentation(settings: vm.settings)
    }

    private var transcriptionModelDetail: String {
        switch vm.transcriptionController.modelState {
        case .notDownloaded:
            return "Required for local transcription and speaker detection."
        case .downloading:
            return "Downloading the speech model."
        case .ready(let size):
            return "\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) installed."
        case .failed(let message):
            return message
        }
    }

    private var audioQualityBinding: Binding<AudioQuality> {
        Binding(
            get: { vm.settings.audioQuality },
            set: { vm.setAudioQuality($0) }
        )
    }

    private var sourceAudioBinding: Binding<SourceAudioFormat> {
        Binding(
            get: { vm.settings.sourceAudioFormat },
            set: { vm.setSourceAudioFormat($0) }
        )
    }

    private var bitrateBinding: Binding<Double> {
        Binding(
            get: {
                Double(
                    vm.settings.customVideoBitrate
                        ?? vm.settings.autoVideoBitrate
                ) / 1_000_000
            },
            set: { value in
                vm.setCustomVideoBitrate(Int(value.rounded()) * 1_000_000)
            }
        )
    }

}

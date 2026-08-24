import SwiftUI

struct RecordingSettingsPage: View {
    @Bindable var vm: RecorderViewModel
    @State private var showsAdvanced = false

    private var canEdit: Bool {
        vm.state == .idle
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsPageHeader(.init(
                    title: "Recording",
                    detail: "Choose capture quality, file storage, export defaults, and local transcription.",
                    systemImage: "record.circle",
                    status: profileSummary
                ))
                .padding(.bottom, 4)

                videoSection
                exportDefaultsSection
                storageSection
                transcriptionSection
                advancedSection
            }
            .settingsPageContent()
        }
        .background(BlitzUI.projectLibraryBackground)
        .foregroundStyle(.white)
    }

    private var videoSection: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 18) {
                SettingsRowLabel(.init(
                    title: "Recording resolution",
                    detail: resolutionDetail
                ))

                Spacer(minLength: 16)

                Picker("", selection: resolutionBinding) {
                    ForEach(OutputResolution.allCases, id: \.self) { resolution in
                        Text(resolution.displayName)
                            .tag(resolution)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 300)
                .disabled(!canEdit)
            }
            .settingsRow()

            SettingsCardDivider()

            HStack(alignment: .center, spacing: 18) {
                SettingsRowLabel(.init(
                    title: "Source FPS",
                    detail: "30 fps is the best default for most recordings."
                ))

                Spacer(minLength: 16)

                Picker("", selection: frameRateBinding) {
                    ForEach(RecordingSettings.supportedFrameRates, id: \.self) { frameRate in
                        Text("\(frameRate)")
                            .tag(frameRate)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)
                .disabled(!canEdit)
            }
            .settingsRow()

            SettingsCardDivider()

            HStack(alignment: .center, spacing: 18) {
                SettingsRowLabel(.init(
                    title: "Recorded source files",
                    detail: "Separate HEVC masters preserve the best quality for later exports."
                ))

                Spacer(minLength: 16)

                Text(qualityPresentation.sourceEncodingSummary)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.56))
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(.white.opacity(0.05), in: .capsule)
            }
            .settingsRow()
        }
        .settingsCard(.init(
            title: "Recording quality",
            detail: "Applied to new source recordings",
            systemImage: "video.badge.checkmark"
        ))
    }

    private var exportDefaultsSection: some View {
        HStack(alignment: .center, spacing: 18) {
            SettingsRowLabel(.init(
                title: "Default export format",
                detail: "\(vm.settings.outputVideoFormat.plainDescription). Change it per export in the editor."
            ))

            Spacer(minLength: 16)

                Picker("", selection: formatBinding) {
                    ForEach(OutputVideoFormat.allCases, id: \.self) { format in
                        Text(format.displayName)
                            .tag(format)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
                .disabled(!canEdit)
        }
        .settingsRow()
        .settingsCard(.init(
            title: "Export default",
            detail: "The editor can override this per export",
            systemImage: "square.and.arrow.up"
        ))
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

            SettingsCardDivider()

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
        .settingsCard(.init(
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

            SettingsCardDivider()

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
        .settingsCard(.init(
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
        VStack(spacing: 0) {
            DisclosureGroup("Advanced encoding", isExpanded: $showsAdvanced) {
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

                    SettingsCardDivider()

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
                        SettingsCardDivider()

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
                .padding(.top, 14)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.72))
            .settingsRow()
        }
        .settingsCard(.init(
            title: "Advanced",
            detail: "Encoding controls for specialist workflows",
            systemImage: "slider.horizontal.3"
        ))
    }

    private var profileSummary: String {
        qualityPresentation.profileSummary
    }

    private var resolutionDetail: String {
        let dimensions = vm.settings.outputResolution.dimensions(for: vm.settings.layout)
        return "\(dimensions.width) × \(dimensions.height) · \(vm.settings.layout.shortLabel)"
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

    private var resolutionBinding: Binding<OutputResolution> {
        Binding(
            get: { vm.settings.outputResolution },
            set: { vm.setResolution($0) }
        )
    }

    private var frameRateBinding: Binding<Int> {
        Binding(
            get: { vm.settings.framesPerSecond },
            set: { vm.setFrameRate($0) }
        )
    }

    private var formatBinding: Binding<OutputVideoFormat> {
        Binding(
            get: { vm.settings.outputVideoFormat },
            set: { vm.setFormat($0) }
        )
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

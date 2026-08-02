import SwiftUI

struct RecordingSettingsPage: View {
    @Bindable var vm: RecorderViewModel
    @State private var showsAdvanced = false

    private struct RowLabelConfiguration {
        let title: String
        let detail: String
    }

    private var canEdit: Bool {
        vm.state == .idle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Form {
                videoSection
                exportDefaultsSection
                storageSection
                transcriptionSection
                advancedSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .background(.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recording")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.primary)

            Text("Source recording defaults. Export settings can be changed later in the editor.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)

            Text(profileSummary)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(BlitzUI.mint.opacity(0.82))
                .padding(.top, 3)
        }
        .padding(.horizontal, 30)
        .padding(.top, 28)
        .padding(.bottom, 10)
    }

    private var videoSection: some View {
        Section("Recording quality") {
            LabeledContent {
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
            } label: {
                rowLabel(RowLabelConfiguration(
                    title: "Recording resolution",
                    detail: resolutionDetail
                ))
            }

            LabeledContent {
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
            } label: {
                rowLabel(RowLabelConfiguration(
                    title: "Source FPS",
                    detail: "30 fps is the best default for most recordings."
                ))
            }

            LabeledContent {
                Text(qualityPresentation.sourceEncodingSummary)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } label: {
                rowLabel(RowLabelConfiguration(
                    title: "Recorded source files",
                    detail: "Separate HEVC masters set the maximum quality available to exports."
                ))
            }
        }
    }

    private var exportDefaultsSection: some View {
        Section("Export defaults") {
            LabeledContent {
                Picker("", selection: formatBinding) {
                    ForEach(OutputVideoFormat.allCases, id: \.self) { format in
                        Text(format.displayName)
                            .tag(format)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
                .disabled(!canEdit)
            } label: {
                rowLabel(RowLabelConfiguration(
                    title: "Default export format",
                    detail: "\(vm.settings.outputVideoFormat.plainDescription). Change it per export in the editor."
                ))
            }
        }
    }

    private var storageSection: some View {
        Section("Storage") {
            LabeledContent {
                Button("Choose…") {
                    vm.chooseOutputFolder()
                }
                .disabled(!canEdit)
            } label: {
                rowLabel(RowLabelConfiguration(
                    title: "Save recordings to",
                    detail: vm.settings.outputDirectory.path
                ))
            }

            Toggle(
                isOn: Binding(
                    get: { vm.settings.savesSourceFiles },
                    set: { vm.setSourceFilesSaved($0) }
                )
            ) {
                rowLabel(RowLabelConfiguration(
                    title: "Keep editable projects",
                    detail: "Save separate screen, camera, microphone, and system-audio tracks."
                ))
            }
            .toggleStyle(.switch)
            .disabled(!canEdit)
        }
    }

    private var transcriptionSection: some View {
        Section("Transcription") {
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
                rowLabel(RowLabelConfiguration(
                    title: "Automatic transcript and title",
                    detail: "Transcribe finished recordings and rename them from their content."
                ))
            }
            .toggleStyle(.switch)

            LabeledContent {
                transcriptionModelAction
            } label: {
                rowLabel(RowLabelConfiguration(
                    title: "Local speech model",
                    detail: transcriptionModelDetail
                ))
            }

            if case .downloading(let progress, let phase) = vm.transcriptionController.modelState {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: progress)
                        .tint(BlitzUI.mint)
                    Text(phase)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var transcriptionModelAction: some View {
        switch vm.transcriptionController.modelState {
        case .notDownloaded, .failed:
            Button("Download") {
                vm.transcriptionController.downloadModels()
            }
        case .downloading:
            ProgressView()
                .controlSize(.small)
                .frame(width: 40, height: 40)
        case .ready:
            Button("Remove") {
                vm.transcriptionController.removeModels()
            }
        }
    }

    private var advancedSection: some View {
        Section {
            DisclosureGroup("Advanced encoding", isExpanded: $showsAdvanced) {
                VStack(spacing: 14) {
                    LabeledContent {
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
                    } label: {
                        rowLabel(RowLabelConfiguration(
                            title: "Video detail override",
                            detail: qualityPresentation.bitrateOverrideDetail
                        ))
                    }

                    Divider()

                    LabeledContent {
                        Picker("", selection: audioQualityBinding) {
                            ForEach(AudioQuality.allCases, id: \.self) { quality in
                                Text(quality.displayName)
                                    .tag(quality)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                        .disabled(!canEdit)
                    } label: {
                        rowLabel(RowLabelConfiguration(
                            title: "Audio quality",
                            detail: vm.settings.audioQuality.plainDescription
                        ))
                    }

                    if vm.settings.savesSourceFiles {
                        Divider()

                        LabeledContent {
                            Picker("", selection: sourceAudioBinding) {
                                ForEach(SourceAudioFormat.allCases, id: \.self) { format in
                                    Text(format.displayName)
                                        .tag(format)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 150)
                            .disabled(!canEdit)
                        } label: {
                            rowLabel(RowLabelConfiguration(
                                title: "Source audio format",
                                detail: vm.settings.sourceAudioFormat.plainDescription
                            ))
                        }
                    }
                }
                .padding(.top, 10)
            }
        }
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

    private func rowLabel(
        _ configuration: RowLabelConfiguration
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(configuration.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
            Text(configuration.detail)
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }
}

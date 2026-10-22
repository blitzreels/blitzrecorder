import SwiftUI

struct RecordingTranscriptionSettingsSection: View {
    @Bindable var vm: RecorderViewModel
    @AppStorage(TranscriptionVocabulary.defaultsKey) private var transcriptionVocabulary = ""

    var body: some View {
        VStack(spacing: 0) {
            Toggle(isOn: Binding(
                get: { vm.transcriptionController.isAutomaticEnabled },
                set: { vm.transcriptionController.isAutomaticEnabled = $0 }
            )) {
                SettingsRowLabel(.init(
                    title: "Transcribe automatically",
                    detail: "Create a transcript and title after each recording. Audio never leaves this Mac."
                ))
            }
            .toggleStyle(.blitzSwitch)
            .settingsRow()

            SettingsRowDivider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Speech model").font(BlitzType.label).foregroundStyle(BlitzUI.primaryText)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
                    ForEach(TranscriptionSpeechModel.allCases, id: \.self) { model in
                        speechModelCard(model)
                    }
                }
                speechModelStatus
            }
            .padding(.vertical, 14)

            SettingsRowDivider()

            BlitzAdaptiveRow() {
                SettingsRowLabel(.init(
                    title: "Language",
                    detail: "Choose the spoken language, or let the app detect it."
                ))
                BlitzSegmentedPicker(configuration: .init(
                        title: "Language",
                        options: TranscriptionLanguage.allCases,
                        selection: Binding(
                            get: { vm.transcriptionController.selectedLanguage },
                            set: { vm.transcriptionController.selectedLanguage = $0 }
                        ),
                        label: { $0.title }
                    ))
                    .controlSize(.small)
                    .fixedSize()
            }
            .frame(minHeight: 56)
            .settingsRow()

            SettingsRowDivider()

            BlitzAdaptiveRow() {
                SettingsRowLabel(.init(
                    title: "Speaker count",
                    detail: "Choose 2 for a call with two people, including a shared microphone."
                ))
                BlitzSegmentedPicker(configuration: .init(
                    title: "Speaker count",
                    options: TranscriptionSpeakerCount.allCases,
                    selection: Binding(
                        get: { vm.transcriptionController.speakerCount },
                        set: { vm.transcriptionController.speakerCount = $0 }
                    ),
                    label: { $0.title }
                ))
                .controlSize(.small)
                .fixedSize()
            }
            .frame(minHeight: 56)
            .settingsRow()

            SettingsRowDivider()

            VStack(alignment: .leading, spacing: 8) {
                SettingsRowLabel(.init(
                    title: "Names and vocabulary",
                    detail: "Whisper uses these spellings and saved speaker names as hints. Separate terms with commas."
                ))
                TextField("People, brands, technical terms", text: $transcriptionVocabulary)
                    .textFieldStyle(.plain)
                    .font(BlitzType.body)
                    .padding(10)
                    .background(BlitzUI.controlFill, in: .rect(cornerRadius: BlitzUI.controlRadius))
                    .disabled(vm.transcriptionController.selectedModel == .parakeet)
                if vm.transcriptionController.selectedModel == .parakeet {
                    Text("Select a Whisper model to use vocabulary hints.")
                        .font(BlitzType.caption)
                        .foregroundStyle(BlitzUI.secondaryText)
                }
            }
            .padding(.vertical, 14)
        }
        .settingsSection(.init(
            title: "Transcripts",
            detail: "Speakers are told apart by their voices.",
            systemImage: "waveform.badge.mic"
        ))
    }

    private func speechModelCard(_ model: TranscriptionSpeechModel) -> some View {
        let isSelected = vm.transcriptionController.selectedModel == model
        let installed = vm.transcriptionController.modelStates[model]?.isReady == true
        return Button { vm.transcriptionController.selectedModel = model } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(BlitzType.glyph(15))
                    .foregroundStyle(isSelected ? BlitzUI.accent : BlitzUI.secondaryText)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(model.title).font(BlitzType.label).foregroundStyle(BlitzUI.primaryText)
                        if installed {
                            Text("Installed").font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                        }
                    }
                    Text(model.plainDetail)
                        .font(BlitzType.caption)
                        .foregroundStyle(BlitzUI.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
            .contentShape(.rect)
        }
        .buttonStyle(BlitzSelectionButtonStyle(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var speechModelStatus: some View {
        BlitzAdaptiveRow() {
            switch vm.transcriptionController.modelState {
            case .notDownloaded:
                Text("Download once to transcribe on this Mac.")
                    .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                Button { vm.transcriptionController.downloadModels() } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .blitzButton(.accent)
                .controlSize(.small)
            case .downloading(let progress, let phase):
                ProgressView(value: progress).tint(BlitzUI.accent).frame(maxWidth: .infinity)
                Text(phase).font(BlitzType.caption.monospacedDigit()).foregroundStyle(BlitzUI.secondaryText)
                    .lineLimit(1)
            case .ready(let size):
                Label("\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) installed",
                      systemImage: "checkmark.circle.fill")
                    .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                Button { vm.transcriptionController.removeModels() } label: {
                    Label("Remove", systemImage: BlitzSymbols.delete)
                }
                .blitzButton(.secondary)
                .controlSize(.small)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(BlitzType.caption).foregroundStyle(BlitzUI.warning).fixedSize(horizontal: false, vertical: true)
                Button { vm.transcriptionController.downloadModels() } label: {
                    Label("Try again", systemImage: "arrow.clockwise")
                }
                .blitzButton(.secondary)
                .controlSize(.small)
            }
        }
        .frame(minHeight: BlitzControlMetrics.height(.small))
    }
}

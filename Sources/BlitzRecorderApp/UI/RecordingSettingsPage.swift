import AppKit
import SwiftUI

struct RecordingSettingsPage: View {
    @Bindable var vm: RecorderViewModel
    @State private var showsAdvancedEncoding = false
    @State private var storageDetail = ""
    @State private var storageUnavailable = false

    private var canEdit: Bool {
        vm.state == .idle
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SettingsPageHeader(.init(
                    title: "Recording",
                    detail: "Choose where your files live and what happens after recording.",
                    systemImage: "gearshape",
                    status: nil
                ))
                .padding(.bottom, 4)

                if !canEdit {
                    Label("Recording settings can be changed when this session finishes.", systemImage: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(BlitzUI.warning)
                }

                storageSection
                livePreviewSection
                transcriptionSection

                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        showsAdvancedEncoding.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: showsAdvancedEncoding ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .frame(width: 12)
                            Text("Advanced encoding")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 36)
                    }
                    .buttonStyle(BlitzSelectionButtonStyle(isSelected: false))
                    .pointingHandCursor()
                    .accessibilityValue(showsAdvancedEncoding ? "Expanded" : "Collapsed")
                    .help(showsAdvancedEncoding ? "Hide encoding options" : "Show encoding options")

                    if showsAdvancedEncoding {
                        advancedSection
                    }
                }
            }
            .settingsPageContent()
        }
        .background(BlitzUI.projectLibraryBackground)
        .foregroundStyle(.white)
        .task(id: vm.settings.outputDirectory) { refreshStorageDetail() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshStorageDetail()
        }
    }

    private var livePreviewSection: some View {
        Toggle(
            isOn: Binding(
                get: { vm.isLivePreviewEnabled },
                set: { vm.setLivePreviewEnabled($0) }
            )
        ) {
            SettingsRowLabel(.init(
                title: "Live preview",
                detail: "Pause Mac camera, microphone, screen, and audio previews while idle. Recording still works."
            ))
        }
        .toggleStyle(.blitzSwitch)
        .pointingHandCursor()
        .settingsRow()
        .disabled(!canEdit)
        .settingsSection(.init(
            title: "Before recording",
            detail: nil,
            systemImage: "eye"
        ))
    }

    private var storageSection: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(BlitzUI.mint)
                        .frame(width: 48, height: 48)
                        .background(BlitzUI.mint.opacity(0.08), in: .rect(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(vm.settings.outputDirectory.lastPathComponent)
                            .font(.system(size: 15, weight: .semibold))
                        Text(vm.settings.outputDirectory.path)
                            .font(.system(size: 12))
                            .foregroundStyle(BlitzUI.secondaryText)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .help(vm.settings.outputDirectory.path)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    Button("Change Folder…") { vm.chooseOutputFolder() }
                        .blitzButton(.secondary)
                        .disabled(!canEdit)
                        .accessibilityLabel("Change recordings folder")
                        .help("Choose where new recordings and exports are saved")
                    Button("Show in Finder") {
                        if !NSWorkspace.shared.open(vm.settings.outputDirectory) {
                            storageDetail = "Folder unavailable. Reconnect the drive or choose another folder."
                            storageUnavailable = true
                        }
                    }
                    .blitzButton(.secondary)
                    .help("Open the recordings folder in Finder")
                    Spacer(minLength: 0)
                }

                if !storageDetail.isEmpty {
                    Label(storageDetail, systemImage: storageUnavailable ? "exclamationmark.triangle" : "internaldrive")
                        .font(.system(size: 11))
                        .foregroundStyle(storageUnavailable ? BlitzUI.warning : BlitzUI.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("New recordings and exports use this folder. Existing files stay where they are.")
                    .font(.system(size: 11))
                    .foregroundStyle(BlitzUI.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
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
                    title: "Keep source tracks",
                    detail: "Keep each track for editing later. Uses more disk space."
                ))
            }
            .toggleStyle(.blitzSwitch)
            .pointingHandCursor()
            .settingsRow()
            .disabled(!canEdit)
        }
        .settingsSection(.init(
            title: "Files",
            detail: nil,
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
                    detail: "Create a transcript and title on this Mac, without uploading audio."
                ))
            }
            .toggleStyle(.blitzSwitch)
            .pointingHandCursor()
            .settingsRow()

            SettingsRowDivider()

            HStack(alignment: .center, spacing: 18) {
                SettingsRowLabel(.init(
                    title: "Transcription tool",
                    detail: vm.transcriptionController.selectedModel.detail
                ))
                Spacer(minLength: 16)
                BlitzDropdown(configuration: .init(
                    title: "Transcription tool",
                    selection: Binding(
                        get: { vm.transcriptionController.selectedModel },
                        set: { vm.transcriptionController.selectedModel = $0 }
                    ),
                    options: TranscriptionSpeechModel.allCases.map {
                        .init(value: $0, title: $0.title, detail: $0.detail)
                    }
                ))
                .frame(width: 180)
            }
            .settingsRow()

            SettingsRowDivider()

            HStack(alignment: .center, spacing: 18) {
                SettingsRowLabel(.init(
                    title: "Language",
                    detail: vm.transcriptionController.selectedModel == .parakeet
                        ? "Parakeet detects language automatically."
                        : "Choose French to prevent English language detection."
                ))
                Spacer(minLength: 16)
                BlitzDropdown(configuration: .init(
                    title: "Language",
                    selection: Binding(
                        get: { vm.transcriptionController.selectedLanguage },
                        set: { vm.transcriptionController.selectedLanguage = $0 }
                    ),
                    options: TranscriptionLanguage.allCases.map {
                        .init(value: $0, title: $0.title, detail: nil)
                    }
                ))
                .frame(width: 180)
                .disabled(vm.transcriptionController.selectedModel == .parakeet)
            }
            .settingsRow()

            SettingsRowDivider()

            HStack(alignment: .center, spacing: 18) {
                SettingsRowLabel(.init(
                    title: "Microphone speakers",
                    detail: "Use 2 speakers when two people share one microphone."
                ))
                Spacer(minLength: 16)
                BlitzDropdown(configuration: .init(
                    title: "Microphone speakers",
                    selection: Binding(
                        get: { vm.transcriptionController.speakerCount },
                        set: { vm.transcriptionController.speakerCount = $0 }
                    ),
                    options: TranscriptionSpeakerCount.allCases.map {
                        .init(value: $0, title: $0.title, detail: nil)
                    }
                ))
                .frame(width: 180)
            }
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
            title: "After recording",
            detail: nil,
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
            .blitzButton(.secondary)
            .pointingHandCursor()
        case .downloading:
            Text("Downloading")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(BlitzUI.mint.opacity(0.72))
        case .ready:
            Button("Remove model") {
                vm.transcriptionController.removeModels()
            }
            .blitzButton(.secondary)
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
                    .blitzButton(.secondary)
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

                BlitzDropdown(configuration: .init(
                    title: "Audio quality",
                    selection: audioQualityBinding,
                    options: AudioQuality.allCases.map {
                        .init(value: $0, title: $0.displayName, detail: $0.plainDescription)
                    }
                ))
                .frame(width: 180)
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

                    BlitzDropdown(configuration: .init(
                        title: "Source audio format",
                        selection: sourceAudioBinding,
                        options: SourceAudioFormat.allCases.map {
                            .init(value: $0, title: $0.displayName, detail: $0.plainDescription)
                        }
                    ))
                    .frame(width: 180)
                    .disabled(!canEdit)
                }
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white.opacity(0.72))
        .settingsRow()

    }

    private func refreshStorageDetail() {
        let url = vm.settings.outputDirectory
        let access = OutputDirectoryAccess(
            url: url,
            usesSecurityScopedBookmark: vm.settings.outputDirectoryBookmarkData != nil
        )
        defer { access.stop() }
        guard access.hasSecurityScopedAccess else {
            storageUnavailable = true
            storageDetail = "Folder access needs renewal. Choose the folder again."
            return
        }
        do {
            let values = try url.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey, .volumeNameKey
            ])
            let attributes = try? FileManager.default.attributesOfFileSystem(forPath: url.path)
            let fileSystemCapacity = (attributes?[.systemFreeSize] as? NSNumber)?.int64Value
            guard let available = TakeFileStore.availableCapacityForRecording(
                importantUsageCapacity: values.volumeAvailableCapacityForImportantUsage,
                fallbackCapacity: values.volumeAvailableCapacity.map(Int64.init),
                fileSystemCapacity: fileSystemCapacity
            ) else {
                storageUnavailable = false
                storageDetail = "Available space could not be checked."
                return
            }
            let capacity = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
            storageUnavailable = available < TakeFileStore.minimumAvailableCapacityBytes
            storageDetail = "\(capacity) available on \(values.volumeName ?? "this disk")"
            if storageUnavailable { storageDetail += " · Low disk space" }
        } catch {
            storageUnavailable = true
            storageDetail = "Folder unavailable. Reconnect the drive or choose another folder."
        }
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

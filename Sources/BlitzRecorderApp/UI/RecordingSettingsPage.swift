import AppKit
import SwiftUI

struct RecordingSettingsPage: View {
    @Bindable var vm: RecorderViewModel
    @State private var storageDetail = ""
    @State private var storageUnavailable = false
    @AppStorage(BlitzPreviewPreferences.animatePreviewsKey) private var animatePreviews = true

    private var canEdit: Bool {
        vm.state == .idle
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SettingsPageHeader(.init(
                    title: "Recording",
                    detail: "Choose where your files live and what happens after recording.",
                    status: nil
                ))
                .padding(.bottom, 4)

                if !canEdit {
                    Label("Recording settings can be changed when this session finishes.", systemImage: "info.circle")
                        .font(BlitzType.body)
                        .foregroundStyle(BlitzUI.warning)
                }

                storageSection
                livePreviewSection
                transcriptionSection
                interfaceSection

                qualitySection
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
        VStack(spacing: 0) {
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

            SettingsRowDivider()

            HStack(spacing: 16) {
                SettingsRowLabel(.init(
                    title: "Countdown",
                    detail: "Time to get ready after you press Record. Click Record or press Esc to cancel."
                ))
                BlitzSegmentedPicker(configuration: .init(
                    title: "Countdown",
                    options: RecordingCountdownPreference.options,
                    selection: Binding(get: { vm.countdownSeconds }, set: { vm.setCountdownSeconds($0) }),
                    label: { $0 == 0 ? "Off" : "\($0) s" }
                ))
                .frame(width: 180)
            }
            .settingsRow()
            .disabled(!canEdit)
        }
        .settingsSection(.init(
            title: "Before recording",
            detail: nil,
            systemImage: "eye"
        ))
    }

    private var interfaceSection: some View {
        Toggle(isOn: $animatePreviews) {
            SettingsRowLabel(.init(
                title: "Animate setting previews",
                detail: "Play the small thumbnails in the editor tools on hover. Your video is not affected."
            ))
        }
        .toggleStyle(.blitzSwitch)
        .pointingHandCursor()
        .settingsRow()
        .settingsSection(.init(
            title: "Interface",
            detail: nil,
            systemImage: "sparkles"
        ))
    }

    private var storageSection: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: "folder.fill")
                        .font(BlitzType.glyph(30))
                        .foregroundStyle(BlitzUI.mint)
                        .frame(width: 48, height: 48)
                        .background(BlitzUI.mint.opacity(0.08), in: .rect(cornerRadius: BlitzUI.cardRadius))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Exports")
                            .font(BlitzType.label)
                            .foregroundStyle(BlitzUI.secondaryText)
                        Text(vm.settings.outputDirectory.lastPathComponent)
                            .font(BlitzType.headline)
                        Text(vm.settings.outputDirectory.path)
                            .font(BlitzType.body)
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
                        .accessibilityLabel("Change export folder")
                        .help("Choose where finished videos are saved. Source files stay in the library.")
                    Button("Show in Finder") {
                        if !NSWorkspace.shared.open(vm.settings.outputDirectory) {
                            storageDetail = "Folder unavailable. Reconnect the drive or choose another folder."
                            storageUnavailable = true
                        }
                    }
                    .blitzButton(.secondary)
                    .help("Open the export folder in Finder")
                    Spacer(minLength: 0)
                }

                if !storageDetail.isEmpty {
                    Label(storageDetail, systemImage: storageUnavailable ? "exclamationmark.triangle" : "internaldrive")
                        .font(BlitzType.caption)
                        .foregroundStyle(storageUnavailable ? BlitzUI.warning : BlitzUI.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Finished videos are saved here. Changing this folder keeps your source files and project library in place.")
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .settingsRow()

            SettingsRowDivider()

            VStack(alignment: .leading, spacing: 14) {
                SettingsRowLabel(.init(
                    title: "Recording sources",
                    detail: "Choose where new source tracks are stored. Existing projects stay in your library."
                ))
                Text(vm.settings.sourceStorage.url.path)
                    .font(BlitzType.body)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(vm.settings.sourceStorage.url.path)
                HStack(spacing: 8) {
                    Button("Change Folder…") { vm.chooseSourceFolder() }
                        .blitzButton(.secondary)
                        .disabled(!canEdit)
                        .accessibilityLabel("Change recording sources folder")
                        .help("Choose a source library folder for new recordings. Existing files stay where they are.")
                    Button("Show in Finder") {
                        NSWorkspace.shared.open(vm.settings.sourceStorage.url)
                    }
                    .blitzButton(.secondary)
                    .help("Open the source library. Other linked project folders also stay in Projects.")
                    Spacer(minLength: 0)
                }
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
            .pointingHandCursor()
            .settingsRow()

            SettingsRowDivider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Speech model").font(BlitzType.label).foregroundStyle(BlitzUI.primaryText)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(TranscriptionSpeechModel.allCases, id: \.self) { model in
                        speechModelCard(model)
                    }
                }
                speechModelStatus
            }
            .padding(.vertical, 14)

            SettingsRowDivider()

            HStack(alignment: .center, spacing: 18) {
                SettingsRowLabel(.init(
                    title: "Language",
                    detail: vm.transcriptionController.selectedModel == .parakeet
                        ? "Detected automatically for each recording."
                        : "Pick a language if Automatic guesses wrong."
                ))
                Spacer(minLength: 16)
                if vm.transcriptionController.selectedModel == .parakeet {
                    Label("Automatic", systemImage: "globe")
                        .font(BlitzType.label)
                        .foregroundStyle(BlitzUI.secondaryText)
                } else {
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
            }
            .frame(minHeight: 56)
            .settingsRow()
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
                    .foregroundStyle(isSelected ? BlitzUI.mint : BlitzUI.secondaryText)
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
        HStack(spacing: 12) {
            switch vm.transcriptionController.modelState {
            case .notDownloaded:
                Text("Download once to transcribe on this Mac.")
                    .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                Spacer(minLength: 8)
                Button { vm.transcriptionController.downloadModels() } label: {
                    Label("Download", systemImage: "arrow.down.circle.fill")
                }
                .blitzButton(.accent)
                .controlSize(.small)
            case .downloading(let progress, let phase):
                ProgressView(value: progress).tint(BlitzUI.mint).frame(maxWidth: .infinity)
                Text(phase).font(BlitzType.caption.monospacedDigit()).foregroundStyle(BlitzUI.secondaryText)
                    .lineLimit(1)
            case .ready(let size):
                Label("\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) installed",
                      systemImage: "checkmark.seal.fill")
                    .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                Spacer(minLength: 8)
                Button { vm.transcriptionController.removeModels() } label: {
                    Label("Remove", systemImage: "trash.fill")
                }
                .blitzButton(.secondary)
                .controlSize(.small)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(BlitzType.caption).foregroundStyle(BlitzUI.warning).lineLimit(2)
                Spacer(minLength: 8)
                Button { vm.transcriptionController.downloadModels() } label: {
                    Label("Try again", systemImage: "arrow.clockwise")
                }
                .blitzButton(.secondary)
                .controlSize(.small)
            }
        }
        .frame(height: BlitzControlMetrics.height(.small))
    }

    private var qualitySection: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 18) {
                    SettingsRowLabel(.init(
                        title: "Video bitrate",
                        detail: vm.settings.customVideoBitrate == nil
                            ? "Automatic · \(qualityPresentation.finalBitrateLabel) for your resolution and frame rate."
                            : "Custom · Higher keeps more detail and makes bigger files."
                    ))
                    Spacer(minLength: 16)
                    BlitzSegmentedPicker(configuration: .init(
                        title: "Video bitrate",
                        options: [false, true],
                        selection: Binding(
                            get: { vm.settings.customVideoBitrate != nil },
                            set: { custom in
                                vm.setCustomVideoBitrate(custom ? vm.settings.autoVideoBitrate : nil)
                            }
                        ),
                        label: { $0 ? "Custom" : "Automatic" }
                    ))
                    .controlSize(.small)
                    .fixedSize()
                }
                if vm.settings.customVideoBitrate != nil {
                    HStack(spacing: 12) {
                        Slider(
                            value: bitrateBinding,
                            in: Double(RecordingSettings.minCustomVideoBitrate / 1_000_000)
                                ... Double(RecordingSettings.maxCustomVideoBitrate / 1_000_000),
                            step: 1
                        )
                        .tint(BlitzUI.mint)
                        Text("\(Int(bitrateBinding.wrappedValue)) Mbps")
                            .font(BlitzType.label.monospacedDigit())
                            .frame(width: 70, alignment: .trailing)
                    }
                    .padding(.bottom, 4)
                }
            }
            .padding(.vertical, 12)
            .disabled(!canEdit)
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
            .settingsRow()

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
                .settingsRow()
            }
        }
        .settingsSection(.init(
            title: "Quality",
            detail: "Defaults suit most videos.",
            systemImage: "dial.medium"
        ))
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

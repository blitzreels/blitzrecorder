import AppKit
import SwiftUI

struct RecordingSettingsPage: View {
    @Bindable var vm: RecorderViewModel
    @State private var storageDetail = ""
    @State private var storageUnavailable = false
    @AppStorage(BlitzPreviewPreferences.animatePreviewsKey) private var animatePreviews = true

    private static let folderUnavailableDetail = "Folder unavailable. Reconnect the drive or choose another folder."

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
                RecordingTranscriptionSettingsSection(vm: vm)
                interfaceSection

                qualitySection
            }
            .settingsPageContent()
        }
        .background(BlitzUI.projectLibraryBackground)
        .foregroundStyle(BlitzUI.primaryText)
        .task(id: vm.settings.outputDirectory) { refreshStorageDetail() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshStorageDetail()
        }
    }

    private var livePreviewSection: some View {
        VStack(spacing: 0) {
            Toggle(isOn: Binding(
                get: { vm.settings.includesRecorderUI },
                set: { vm.setRecorderUIIncluded($0) }
            )) {
                SettingsRowLabel(.init(
                    title: "Record BlitzRecorder UI",
                    detail: "Include BlitzRecorder in display recordings and choose its window as a screen source. When off, it is also hidden from screen sharing where the call allows it; sharing your whole screen in Zoom may still show it."
                ))
            }
            .toggleStyle(.blitzSwitch)
            .settingsRow()
            .disabled(!canEdit)

            SettingsRowDivider()

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
            .settingsRow()
            .disabled(!canEdit)

            SettingsRowDivider()

            BlitzAdaptiveRow() {
                SettingsRowLabel(.init(
                    title: "Countdown",
                    detail: "Time to get ready after you press Record. Click Record or press Esc to cancel."
                ))
                BlitzSegmentedPicker(configuration: .init(
                    title: "Countdown",
                    options: RecordingCountdownPreference.options,
                    selection: Binding(get: { vm.session.countdownSeconds }, set: { vm.setCountdownSeconds($0) }),
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
                        .foregroundStyle(BlitzUI.accent)
                        .frame(width: 48, height: 48)
                        .background(BlitzUI.accent.opacity(0.08), in: .rect(cornerRadius: BlitzUI.cardRadius))
                    VStack(alignment: .leading, spacing: 5) {
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
                            storageDetail = Self.folderUnavailableDetail
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
                    title: "Libraries",
                    detail: "Every folder your recordings are read from, disk by disk. New recordings go to one of them."
                ))
                ProjectLibraryLocationsSettings(vm: vm, canEdit: canEdit)
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
            .settingsRow()
            .disabled(!canEdit)
        }
        .settingsSection(.init(
            title: "Files",
            detail: nil,
            systemImage: "internaldrive"
        ))
    }

    private var qualitySection: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                BlitzAdaptiveRow() {
                    SettingsRowLabel(.init(
                        title: "Video bitrate",
                        detail: vm.settings.customVideoBitrate == nil
                            ? "Automatic · \(qualityPresentation.finalBitrateLabel) for your resolution and frame rate."
                            : "Custom · Higher keeps more detail and makes bigger files."
                    ))
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
                        .tint(BlitzUI.accent)
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

            BlitzAdaptiveRow() {
                SettingsRowLabel(.init(
                    title: "Audio quality",
                    detail: vm.settings.audioQuality.plainDescription
                ))

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

                BlitzAdaptiveRow() {
                    SettingsRowLabel(.init(
                        title: "Source audio format",
                        detail: vm.settings.sourceAudioFormat.plainDescription
                    ))

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
            storageDetail = Self.folderUnavailableDetail
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

import AppKit
import SwiftUI

struct RecordingStorageStatus: Equatable {
    var text = ""
    var isWarning = false

    static let unavailable = Self(text: "Folder unavailable. Reconnect the drive or choose another folder.", isWarning: true)

    static func read(_ location: RecordingStorageLocation) -> Self {
        let url = location.url
        let access = OutputDirectoryAccess(url: url, usesSecurityScopedBookmark: location.bookmarkData != nil)
        defer { access.stop() }
        guard access.hasSecurityScopedAccess else {
            return .init(text: "Folder access needs renewal. Choose the folder again.", isWarning: true)
        }
        do {
            let values = try url.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey, .volumeNameKey
            ])
            let attributes = try? FileManager.default.attributesOfFileSystem(forPath: url.path)
            guard let available = TakeFileStore.availableCapacityForRecording(
                importantUsageCapacity: values.volumeAvailableCapacityForImportantUsage,
                fallbackCapacity: values.volumeAvailableCapacity.map(Int64.init),
                fileSystemCapacity: (attributes?[.systemFreeSize] as? NSNumber)?.int64Value
            ) else {
                return .init(text: "Available space could not be checked.")
            }
            let capacity = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
            let isLow = available < TakeFileStore.minimumAvailableCapacityBytes
            return .init(text: "On \(values.volumeName ?? "this disk") · \(capacity) free\(isLow ? " · Low disk space" : "")",
                         isWarning: isLow)
        } catch {
            return .unavailable
        }
    }
}

/// The two places files are written, each named for what it holds, so the disk a new recording lands on is never a guess.
struct RecordingStorageDestinations: View {
    @Bindable var vm: RecorderViewModel
    let canEdit: Bool
    @State private var recordingStatus = RecordingStorageStatus()
    @State private var exportStatus = RecordingStorageStatus()

    private static let otherFolder = "other-folder"

    private var recording: RecordingStorageLocation { vm.settings.sourceStorage }
    private var export: RecordingStorageLocation {
        .init(url: vm.settings.outputDirectory, bookmarkData: vm.settings.outputDirectoryBookmarkData)
    }

    var body: some View {
        VStack(spacing: 0) {
            StorageDestinationRow(configuration: .init(
                title: "New recordings", url: recording.url, status: recordingStatus,
                control: recordingPicker, showInFinder: { show(.init(url: recording.url, isRecording: true)) }
            ))
            SettingsRowDivider()
            StorageDestinationRow(configuration: .init(
                title: "Finished videos", url: export.url, status: exportStatus,
                control: changeExportFolder, showInFinder: { show(.init(url: export.url, isRecording: false)) }
            ))
        }
        .task(id: [recording.url, export.url]) { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private var recordingPicker: some View {
        BlitzDropdown(configuration: .init(
            title: "New recordings folder",
            selection: Binding(get: { Self.path(recording.url) }, set: choose),
            options: recordingOptions,
            menuWidth: 360,
            width: .content
        ))
        .disabled(!canEdit)
        .help("Choose the disk and folder new recordings are saved to")
    }

    private var changeExportFolder: some View {
        Button("Change Folder…") { vm.chooseOutputFolder() }
            .blitzButton(.secondary)
            .disabled(!canEdit)
            .accessibilityLabel("Change export folder")
            .help("Choose where finished videos are saved")
    }

    private var recordingOptions: [BlitzDropdownOption<String>] {
        let locations = vm.libraryLocations.locations
        let current = Self.path(recording.url)
        var options: [BlitzDropdownOption<String>] = locations.map { location in
            .init(value: location.url.path, title: Self.title(location.url),
                  detail: location.isConnected ? "\(Self.count(location.recordingCount ?? 0)) · \(location.url.path)"
                      : "Not connected · \(location.url.path)",
                  isEnabled: location.isConnected)
        }
        if !locations.contains(where: { $0.url.path == current }) {
            options.insert(.init(value: current, title: Self.title(recording.url), detail: current), at: 0)
        }
        options += vm.libraryLocations.suggestions.map { suggestion in
            .init(value: suggestion.url.path, title: Self.title(suggestion.url),
                  detail: "\(Self.count(suggestion.recordingCount)) · \(suggestion.url.path)")
        }
        options.append(.init(value: Self.otherFolder, title: "Other folder…", detail: "Pick any folder, on any disk"))
        return options
    }

    private func choose(_ value: String) {
        if value == Self.otherFolder {
            vm.chooseSourceFolder()
        } else if value != Self.path(recording.url) {
            vm.setRecordingFolder(URL(fileURLWithPath: value, isDirectory: true))
        }
    }

    private struct FinderRequest {
        let url: URL
        let isRecording: Bool
    }

    private func show(_ request: FinderRequest) {
        guard !NSWorkspace.shared.open(request.url) else { return }
        if request.isRecording { recordingStatus = .unavailable } else { exportStatus = .unavailable }
    }

    private func refresh() {
        recordingStatus = .read(recording)
        exportStatus = .read(export)
    }

    private static func path(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func title(_ url: URL) -> String {
        "\(ProjectLibraryLocations.diskName(of: url)) · \(url.lastPathComponent)"
    }

    private static func count(_ recordings: Int) -> String {
        "\(recordings) recording\(recordings == 1 ? "" : "s")"
    }
}

private struct StorageDestinationRow<Control: View>: View {
    struct Configuration {
        let title: String
        let url: URL
        let status: RecordingStorageStatus
        let control: Control
        let showInFinder: () -> Void
    }

    let configuration: Configuration

    var body: some View {
        BlitzAdaptiveRow {
            HStack(alignment: .top, spacing: 10) {
                BlitzSymbol(configuration: .init(
                    name: ProjectLibraryLocations.isExternal(configuration.url) ? "externaldrive" : "internaldrive", size: 16
                ))
                .foregroundStyle(BlitzUI.secondaryText)
                .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(configuration.title).font(BlitzType.callout).foregroundStyle(BlitzUI.primaryText)
                    Text(configuration.status.text.isEmpty ? " " : configuration.status.text)
                        .font(BlitzType.body)
                        .foregroundStyle(configuration.status.isWarning ? BlitzUI.warning : BlitzUI.supportingText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(configuration.url.path)
                        .font(BlitzType.caption)
                        .foregroundStyle(BlitzUI.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(configuration.url.path)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                configuration.control
                Button("Show in Finder", action: configuration.showInFinder)
                    .blitzButton(.quiet)
                    .help("Open this folder in Finder")
            }
            .fixedSize()
        }
        .settingsRow()
    }
}

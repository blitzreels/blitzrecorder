import SwiftUI

/// Tells the Recordings list why recordings are missing: a library disk that is unplugged, or a library on a
/// connected disk the app does not read yet, with the one action that brings them in.
struct ProjectLibraryLocationsBar: View {
    @Bindable var vm: RecorderViewModel
    @State private var dismissed: Set<String> = []

    private var offline: [ProjectLibraryLocations.Location] {
        vm.libraryLocations.offline.filter { !dismissed.contains($0.id) }
    }

    private var suggestions: [ProjectLibraryLocations.Suggestion] {
        vm.libraryLocations.suggestions.filter { !dismissed.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(offline) { location in
                bar(.init(
                    id: location.id, symbol: "externaldrive.badge.xmark",
                    message: location.isRecordingDestination
                        ? "“\(location.diskName)” isn’t connected. Plug it in to see its recordings and record to it."
                        : "“\(location.diskName)” isn’t connected. Its recordings come back when you plug it in.",
                    action: nil
                ))
            }
            ForEach(suggestions) { suggestion in
                bar(.init(
                    id: suggestion.id, symbol: "externaldrive",
                    message: "\(suggestion.recordingCount) recording\(suggestion.recordingCount == 1 ? "" : "s") on "
                        + "“\(suggestion.diskName)” in \(suggestion.url.lastPathComponent) aren’t in your library.",
                    action: .init(title: "Add to Library") { vm.addProjectLibrary(suggestion.url) }
                ))
            }
        }
    }

    private struct Bar {
        struct Action {
            let title: String
            let perform: () -> Void
        }

        let id: String
        let symbol: String
        let message: String
        let action: Action?
    }

    private func bar(_ bar: Bar) -> some View {
        HStack(spacing: 12) {
            BlitzSymbol(configuration: .init(name: bar.symbol, size: 16))
                .foregroundStyle(BlitzUI.secondaryText)
            Text(bar.message)
                .font(BlitzType.label)
                .foregroundStyle(BlitzUI.supportingText)
                .lineLimit(2)
            Spacer(minLength: 8)
            if let action = bar.action {
                Button(action.title, action: action.perform).blitzButton(.secondary)
            }
            Button("Library Settings…") { vm.showSettings(.recording) }
                .blitzButton(.quiet)
            BlitzToolbarButton(configuration: .init(
                title: "Dismiss", symbolName: "xmark", showsTitle: false,
                action: { dismissed.insert(bar.id) }
            ))
        }
        .blitzWorkspaceToolbar()
    }
}

/// The Libraries list in Settings: every folder the Recordings list reads, disk by disk, which one new recordings go
/// to, and libraries found on connected disks.
struct ProjectLibraryLocationsSettings: View {
    @Bindable var vm: RecorderViewModel
    let canEdit: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(vm.libraryLocations.locations) { location in row(location) }
            ForEach(vm.libraryLocations.suggestions) { suggestion in
                HStack(spacing: 10) {
                    BlitzSymbol(configuration: .init(name: "externaldrive.badge.plus", size: 16))
                        .foregroundStyle(BlitzUI.secondaryText)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Found on “\(suggestion.diskName)”").font(BlitzType.body)
                        Text("\(suggestion.recordingCount) recordings · \(suggestion.url.path)")
                            .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    Button("Add") { vm.addProjectLibrary(suggestion.url) }
                        .blitzButton(.secondary)
                        .disabled(!canEdit)
                }
            }
            HStack(spacing: 8) {
                Button("Add Library Folder…") { vm.chooseProjectLibraryToAdd() }
                    .blitzButton(.secondary)
                    .disabled(!canEdit)
                    .help("Read recordings from another folder, such as one on an external disk")
                Button("Record To Another Folder…") { vm.chooseSourceFolder() }
                    .blitzButton(.quiet)
                    .disabled(!canEdit)
                    .help("Choose where new recordings are saved. Existing libraries stay in the list.")
                Spacer(minLength: 0)
            }
            .padding(.top, 4)
        }
        .task { vm.refreshLibraryLocations() }
    }

    private func row(_ location: ProjectLibraryLocations.Location) -> some View {
        HStack(spacing: 10) {
            BlitzSymbol(configuration: .init(name: symbol(location), size: 16))
            .foregroundStyle(location.isConnected ? BlitzUI.primaryText : BlitzUI.warning)
            .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(location.diskName).font(BlitzType.body)
                    if location.isRecordingDestination {
                        Text("New recordings")
                            .font(BlitzType.footnote).foregroundStyle(BlitzUI.supportingText)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(BlitzUI.quietFill, in: .capsule)
                    }
                }
                Text(subtitle(location))
                    .font(BlitzType.caption)
                    .foregroundStyle(location.isConnected ? BlitzUI.secondaryText : BlitzUI.warning)
                    .lineLimit(1).truncationMode(.middle)
                    .help(location.url.path)
            }
            Spacer(minLength: 8)
            Button("Show") { NSWorkspace.shared.open(location.url) }
                .blitzButton(.quiet)
                .disabled(!location.isConnected)
                .help("Show this library in Finder")
            if !location.isRecordingDestination {
                Button("Remove") { vm.removeProjectLibrary(location.url) }
                    .blitzButton(.quiet)
                    .disabled(!canEdit)
                    .help("Stop showing these recordings. Their files stay on the disk.")
            }
        }
    }

    private func symbol(_ location: ProjectLibraryLocations.Location) -> String {
        if !location.isConnected { return "externaldrive.badge.xmark" }
        return location.isExternal ? "externaldrive" : "internaldrive"
    }

    private func subtitle(_ location: ProjectLibraryLocations.Location) -> String {
        guard location.isConnected else { return "Not connected · \(location.url.path)" }
        let count = location.recordingCount ?? 0
        return "\(count) recording\(count == 1 ? "" : "s") · \(location.url.path)"
    }
}

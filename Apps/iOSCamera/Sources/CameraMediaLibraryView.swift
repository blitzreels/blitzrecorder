import BlitzRecorderCore
import BlitzRecorderDesign
import SwiftUI

struct CameraMediaLibraryView: View {
    @Bindable var store: CameraCompanionStore
    @State private var confirmsDeleteAll = false

    var body: some View {
        NavigationStack {
            List {
                if !store.hasPairedMac {
                    BlitzRecorderMacInstallCard()
                        .listRowInsets(.init(top: 8, leading: 16, bottom: 16, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                if store.pendingRecordings.isEmpty {
                    BlitzEmptyState(configuration: .init(
                        symbol: BlitzSymbols.library,
                        title: "No clips yet",
                        detail: "Clips you record for your Mac stay here until it imports them.",
                        action: nil
                    ))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(store.pendingRecordings) { recording in
                            clipRow(recording)
                        }
                    } header: {
                        Text(summary)
                            .font(BlitzType.captionEmphasis)
                            .foregroundStyle(BlitzUI.secondaryText)
                            .textCase(nil)
                    }
                }
                Section {
                    Toggle("Keep clips after your Mac imports them", isOn: $store.keepsRecordingsAfterMacImport)
                        .toggleStyle(.blitzSwitch)
                    if !store.pendingRecordings.isEmpty {
                        Button("Delete All Clips", systemImage: BlitzSymbols.delete, role: .destructive) {
                            confirmsDeleteAll = true
                        }
                        .blitzButton(.quiet)
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(BlitzUI.projectLibraryBackground)
            .navigationTitle("Clips")
            .confirmationDialog(
                "Delete all clips?",
                isPresented: $confirmsDeleteAll,
                titleVisibility: .visible
            ) {
                Button("Delete All", role: .destructive) {
                    store.deleteAllPendingRecordings()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes \(clipCount) from this iPhone. Clips your Mac already imported stay on your Mac.")
            }
        }
        .modifier(MinimizesTabBarOnScroll())
    }

    private var clipCount: String {
        store.pendingRecordingCount == 1 ? "1 clip" : "\(store.pendingRecordingCount) clips"
    }

    private var summary: String {
        let freeSpace = store.freeStorageLabel == "Checking space" ? nil : "\(store.freeStorageLabel) free"
        return [clipCount, freeSpace].compactMap { $0 }.joined(separator: " · ")
    }

    private func clipRow(_ recording: CameraPendingRecording) -> some View {
        NavigationLink {
            CameraRecordingPlaybackView(
                recording: recording,
                retryImport: { store.retryPendingImport(recording) },
                delete: { store.deletePendingRecording(recording) }
            )
        } label: {
            RecordingLibraryRow(recording: recording)
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Delete", systemImage: BlitzSymbols.delete, role: .destructive) {
                store.deletePendingRecording(recording)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button("Send Again", systemImage: "arrow.clockwise") {
                store.retryPendingImport(recording)
            }
            .tint(BlitzUI.accent)
            .disabled(recording.takeID == nil)
        }
        .contextMenu {
            Button("Send Again", systemImage: "arrow.clockwise") {
                store.retryPendingImport(recording)
            }
            .disabled(recording.takeID == nil)
            Button("Delete", systemImage: BlitzSymbols.delete, role: .destructive) {
                store.deletePendingRecording(recording)
            }
        }
    }
}

private struct MinimizesTabBarOnScroll: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

private struct BlitzRecorderMacInstallCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                BlitzAppIcon(image: Bundle.main.blitzRecorderMacIcon.map(Image.init(uiImage:)), size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Get BlitzRecorder for Mac")
                        .font(BlitzType.headline)
                        .foregroundStyle(BlitzUI.primaryText)
                    Text("It pairs with this iPhone and runs every recording.")
                        .font(BlitzType.body)
                        .foregroundStyle(BlitzUI.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Link(destination: BlitzRecorderProductIdentity.macInstallURL) {
                Label("Open blitzrecorder.com", systemImage: BlitzSymbols.openLink)
                    .frame(maxWidth: .infinity)
            }
            .blitzButton(.accent)
            .controlSize(.large)
        }
        .padding(16)
        .background { BlitzSelectedBackground(cornerRadius: BlitzUI.surfaceRadius) }
    }
}

#Preview("Clips") {
    CameraMediaLibraryView(store: CameraCompanionStore())
}

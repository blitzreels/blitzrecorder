import BlitzRecorderDesign
import SwiftUI

struct ConnectionDiagnosticsView: View {
    @Bindable var store: CameraCompanionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Connection") {
                    DiagnosticRow(title: "Status", value: store.connectionTitle)
                    DiagnosticRow(title: "Message", value: store.statusMessage)
                    DiagnosticRow(title: "Port", value: store.listeningPortLabel)
                    DiagnosticRow(title: "Pairing Code", value: store.pairingCode)
                }

                Section("Device") {
                    DiagnosticRow(title: "Live view", value: store.previewHealthLabel)
                    DiagnosticRow(title: "Free space", value: store.freeStorageLabel)
                    DiagnosticRow(title: "Phone temp", value: store.thermalStateLabel)
                    DiagnosticRow(title: "Saved clips", value: "\(store.pendingRecordingCount)")
                }

                Section {
                    Button("Find Mac Again", systemImage: "arrow.clockwise") {
                        store.retryConnection()
                    }
                    .blitzButton(.secondary)
                    .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(BlitzUI.panelBackground)
            .navigationTitle("Connection")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct DiagnosticRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(BlitzType.captionEmphasis)
                .foregroundStyle(BlitzUI.secondaryText)
            Text(value)
                .font(BlitzType.body)
                .foregroundStyle(BlitzUI.primaryText)
                .textSelection(.enabled)
        }
    }
}

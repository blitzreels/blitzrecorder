import SwiftUI

struct EditorZoomPointInspector: View {
    struct Configuration {
        let vm: RecorderViewModel
        let playback: EditorPlaybackController
        let point: ScreenZoomKeyframe
        let selection: Binding<UUID?>
    }
    let configuration: Configuration
    @State private var time = ""
    @State private var magnification = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Zoom point").font(.system(size: 12, weight: .semibold))
            HStack {
                Text("Time")
                TextField("0:00", text: $time).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Zoom point time").onSubmit(save)
            }
            HStack {
                Text("Magnification")
                TextField("1.0", text: $magnification).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Zoom point magnification").onSubmit(save)
                Text("×")
            }
            HStack {
                Button("Apply", action: save).blitzButton(.secondary)
                Spacer()
                Button("Remove", role: .destructive) {
                    guard var edits = configuration.vm.lastExportedProject?.edits else { return }
                    edits.zoom.keyframes.removeAll { $0.id == configuration.point.id }
                    if configuration.vm.applyTimelineEdits(.init(edits: edits, actionName: "Remove Zoom Point")) {
                        configuration.selection.wrappedValue = nil
                    }
                }.blitzButton(.quiet)
            }.controlSize(.small)
            if let error { Text(error).foregroundStyle(BlitzUI.warning) }
        }
        .font(.system(size: 11))
        .onChange(of: configuration.point, initial: true) { _, point in
            time = EditorPlaybackPosition.display(point.time)
            magnification = String(format: "%.2f", 1 / max(0.25, 1 - point.amount))
            error = nil
        }
    }

    private func save() {
        guard let seconds = EditorPlaybackPosition.parse(.init(text: time, duration: configuration.playback.duration)),
              let scale = Double(magnification.replacingOccurrences(of: ",", with: ".")), (1...4).contains(scale) else {
            error = "Enter a valid time and magnification from 1× to 4×."
            return
        }
        guard var edits = configuration.vm.lastExportedProject?.edits,
              let index = edits.zoom.keyframes.firstIndex(where: { $0.id == configuration.point.id }) else { return }
        edits.zoom.keyframes[index].time = seconds
        edits.zoom.keyframes[index].amount = 1 - 1 / scale
        edits.zoom.keyframes.sort { $0.time < $1.time }
        configuration.playback.pauseForEditing()
        if configuration.vm.applyTimelineEdits(.init(edits: edits, actionName: "Edit Zoom Point")) {
            configuration.playback.seek(to: seconds)
            error = nil
        } else { error = configuration.vm.detailMessage }
    }
}

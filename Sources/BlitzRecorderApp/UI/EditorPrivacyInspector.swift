import SwiftUI

struct EditorPrivacyInspector: View {
    struct Configuration {
        let vm: RecorderViewModel
        let playback: EditorPlaybackController
        let session: PrivacyEditingSession
    }

    let configuration: Configuration
    private enum TimeField { case start, end }
    @FocusState private var timeField: TimeField?
    @State private var startText = "0"
    @State private var endText = "0"
    @State private var timingError: String?
    @State private var timingMaskID: UUID?

    private var session: PrivacyEditingSession { configuration.session }
    private var sources: [SceneLayerKind] {
        [.screen, .camera].filter { configuration.playback.hideableKinds.contains($0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Privacy masks").font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 0)
                    Button("Add mask", systemImage: "plus") { session.add() }
                        .blitzButton(.accent).controlSize(.small)
                        .disabled(sources.isEmpty)
                }
                Text(session.isDrawing ? "Drag over the area to hide in the video preview."
                     : "Select a mask on the video to move or resize it.")
                    .font(.system(size: 12)).foregroundStyle(BlitzUI.secondaryText)
                if session.isDrawing {
                    Button("Cancel drawing") { session.cancelGesture() }.blitzButton(.quiet)
                }
                if let selected = session.selected {
                    controls(selected)
                    Divider()
                }
                ForEach(Array(session.masks.enumerated()), id: \.element.id) { index, mask in
                    Button { session.select(mask.id) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: mask.style == .cover ? "rectangle.fill" : "drop.halffull")
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Mask \(index + 1) · \(mask.source.rawValue)")
                                Text("\(mask.style.rawValue) · \(SilenceTime.label(mask.start)) – \(SilenceTime.label(mask.end))")
                                    .font(.system(size: 10)).foregroundStyle(BlitzUI.secondaryText)
                            }
                            Spacer(minLength: 0)
                        }.padding(8)
                    }
                    .buttonStyle(BlitzSelectionButtonStyle(isSelected: selected?.id == mask.id))
                    .accessibilityLabel("Select privacy mask \(index + 1)")
                }
                Text("Changes save automatically. Use Cover to make information unreadable.")
                    .font(.system(size: 11)).foregroundStyle(BlitzUI.secondaryText)
                if let error = timingError ?? session.error {
                    Text(error).font(.system(size: 11)).foregroundStyle(BlitzUI.warning)
                }
            }.padding(14)
        }
        .task { session.configure(.init(vm: configuration.vm, playback: configuration.playback)) }
        .onChange(of: timeField) { old, new in
            if old != nil { saveTimes() }
            if new == nil { refreshTimes() }
        }
        .onChange(of: session.selectedID, initial: true) { _, _ in refreshTimes() }
        .onChange(of: session.selected?.start) { _, _ in refreshTimes() }
        .onChange(of: session.selected?.end) { _, _ in refreshTimes() }
    }

    private var selected: PrivacyMask? { session.selected }

    private func controls(_ mask: PrivacyMask) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            BlitzFormDropdown(configuration: .init(title: "Source", selection: Binding(
                get: { session.selected?.source ?? mask.source },
                set: { value in if var mask = session.selected { mask.source = value; session.update(mask) } }
            ), options: sources.map { .init(value: $0, title: $0.rawValue, detail: nil) }))
            BlitzFormDropdown(configuration: .init(title: "Mask", selection: Binding(
                get: { session.selected?.style ?? mask.style },
                set: { value in if var mask = session.selected { mask.style = value; session.update(mask) } }
            ), options: PrivacyMask.Style.allCases.map { .init(value: $0, title: $0.rawValue, detail: nil) }))
            HStack(spacing: 8) {
                Text("From").font(.system(size: 11))
                TextField("0:00", text: $startText).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Mask start time").focused($timeField, equals: .start).onSubmit(saveTimes)
                Text("To").font(.system(size: 11))
                TextField("End", text: $endText).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Mask end time").focused($timeField, equals: .end).onSubmit(saveTimes)
            }
            HStack {
                Button("Entire recording") {
                    guard var mask = session.selected else { return }
                    mask.start = 0; mask.end = configuration.playback.duration; session.update(mask)
                }.blitzButton(.secondary).controlSize(.small)
                Spacer(minLength: 0)
                if !session.isDrawing {
                    Button("Remove", role: .destructive) { session.removeSelected() }
                        .blitzButton(.quiet).controlSize(.small)
                }
            }
            Text("Times refer to the original recording.")
                .font(.system(size: 10)).foregroundStyle(BlitzUI.secondaryText)
        }
    }

    private func refreshTimes() {
        guard timeField == nil, let selected = session.selected else { return }
        timingMaskID = selected.id
        startText = String(format: "%.2f", selected.start)
        endText = String(format: "%.2f", selected.end)
        timingError = nil
    }

    private func saveTimes() {
        guard var mask = session.selected, mask.id == timingMaskID else { return }
        guard let start = EditorPlaybackPosition.parse(.init(text: startText, duration: configuration.playback.duration)),
              let end = EditorPlaybackPosition.parse(.init(text: endText, duration: configuration.playback.duration)), end > start else {
            timingError = "End time must be after start time."
            return
        }
        let startChanged = startText != String(format: "%.2f", mask.start)
        let endChanged = endText != String(format: "%.2f", mask.end)
        timingError = nil
        guard startChanged || endChanged else { return }
        if startChanged { mask.start = start }
        if endChanged { mask.end = end }
        session.update(mask)
    }
}

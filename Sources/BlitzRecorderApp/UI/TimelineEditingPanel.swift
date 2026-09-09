import SwiftUI

enum RecordingEditTool: String, CaseIterable {
    case text = "Text"
    case zoom = "Cursor zoom"
}

struct TimelineEditingPanel: View {
    @Bindable var vm: RecorderViewModel
    let playback: EditorPlaybackController
    let tool: RecordingEditTool
    @State private var start = 0.0
    @State private var end = 1.0
    @State private var text = ""
    @State private var editingTextID: UUID?
    @State private var preset = TextOverlayPreset.title
    @State private var magnification = 1.7
    @State private var cursorTrack: RecordingCursorTrack?
    @State private var message: String?
    @State private var messageIsError = false

    private var edits: TimelineEdits { vm.lastExportedProject?.edits ?? .empty }
    private var rangeIsValid: Bool {
        start.isFinite && end.isFinite && start >= 0 && end > start + 0.05 && end <= playback.duration
    }
    private var hasCursorClicks: Bool { cursorTrack?.samples.contains(where: \.clicked) == true }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch tool {
                    case .text: textContent
                    case .zoom: zoomContent
                    }
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            Divider().overlay(.white.opacity(0.05))
            VStack(alignment: .leading, spacing: 8) {
                if let message {
                    Text(message).font(.system(size: 11)).foregroundStyle(
                        messageIsError ? BlitzUI.recordRed : BlitzUI.secondaryText
                    )
                    .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.updatesFrequently)
                }
                if tool == .text {
                    HStack {
                        if editingTextID != nil {
                            Button("Cancel edit") {
                                editingTextID = nil
                                text = ""
                            }
                        }
                        Button(editingTextID == nil ? "Add text" : "Save changes", action: saveText)
                            .buttonStyle(BlitzControlButtonStyle(isProminent: true))
                            .disabled(!rangeIsValid || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Spacer(minLength: 0)
                        Text("⌘Z to undo").font(.system(size: 10)).foregroundStyle(BlitzUI.secondaryText)
                    }
                } else if hasCursorClicks {
                    Button(edits.zoom.isEmpty ? "Apply cursor zoom" : "Update cursor zoom", action: generateZoom)
                        .buttonStyle(BlitzControlButtonStyle(isProminent: true))
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BlitzUI.projectLibraryBackground)
        .foregroundStyle(BlitzUI.primaryText)
        .buttonStyle(BlitzControlButtonStyle(isProminent: false))
        .tint(BlitzUI.mint)
        .onAppear {
            start = min(playback.currentTime, max(0, playback.duration - 1))
            end = min(playback.duration, start + 3)
            magnification = edits.zoom.isEmpty ? 1.7 : edits.zoom.intensity
            if let project = vm.lastExportedProject {
                let url = URL(fileURLWithPath: project.takeDirectoryPath).appendingPathComponent("cursor-track.json")
                if let data = try? Data(contentsOf: url) {
                    cursorTrack = try? JSONDecoder().decode(RecordingCursorTrack.self, from: data)
                }
            }
        }
        .onChange(of: tool) { _, _ in message = nil }
    }

    private var timingFields: some View {
        HStack(spacing: 6) {
            timeField(.init(label: "From", value: $start))
            Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(BlitzUI.secondaryText)
            timeField(.init(label: "To", value: $end))
        }
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(editingTextID == nil ? "Add a text overlay" : "Edit text overlay").font(.headline)
            TextField("Write a title or caption…", text: $text, axis: .vertical)
                .lineLimit(2...3).textFieldStyle(.plain).font(.system(size: 16, weight: .medium))
                .padding(14).background(BlitzUI.cardFill, in: .rect(cornerRadius: 10))
                .onChange(of: text) { _, value in if value.count > 500 { text = String(value.prefix(500)) } }
            HStack(spacing: 6) {
                ForEach(TextOverlayPreset.allCases, id: \.self) { style in
                    Button {
                        preset = style
                    } label: {
                        VStack(spacing: 8) {
                            Text(style == .title ? "Aa" : "Your text")
                                .font(
                                    .system(
                                        size: style == .title ? 24 : 12, weight: style == .title ? .black : .semibold)
                                )
                                .padding(.horizontal, style == .caption ? 10 : 0).padding(.vertical, 4)
                                .background(style == .caption ? Color.black : Color.clear, in: .capsule)
                                .frame(height: 34)
                            Text(style.displayName).font(.system(size: 10, weight: .medium)).lineLimit(1)
                        }.frame(maxWidth: .infinity).padding(.vertical, 8)
                    }.buttonStyle(BlitzSelectionButtonStyle(isSelected: preset == style))
                        .accessibilityLabel(style.displayName).accessibilityAddTraits(
                            preset == style ? .isSelected : [])
                }
            }
            timingFields
            ForEach(edits.textOverlays) { overlay in
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(overlay.text).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text(
                            "\(durationLabel(overlay.start)) – \(durationLabel(overlay.end)) · \(overlay.style.preset.displayName)"
                        )
                        .font(.system(size: 10)).foregroundStyle(BlitzUI.secondaryText)
                    }
                    HStack(spacing: 6) {
                        Button("Preview") { preview(overlay.start + min(0.3, overlay.duration / 2)) }
                        Button("Edit") {
                            start = overlay.start
                            end = overlay.end
                            text = overlay.text
                            preset = overlay.style.preset
                            editingTextID = overlay.id
                        }
                        Button("Remove") {
                            var updated = edits
                            updated.textOverlays.removeAll { $0.id == overlay.id }
                            if apply(.init(edits: updated, actionName: "Remove Text")), editingTextID == overlay.id {
                                editingTextID = nil
                                text = ""
                            }
                        }
                    }
                }.padding(12).blitzCard()
            }
        }
    }

    private var zoomContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            emptyState(
                .init(
                    symbol: "cursorarrow.motionlines",
                    title: hasCursorClicks ? "Follow the action" : "No cursor track on this take",
                    detail: hasCursorClicks
                        ? "Zoom toward clicks, follow the cursor, then ease back to the full screen."
                        : "Record a new take with screen sources saved to use automatic cursor zoom."))
            if hasCursorClicks {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Zoom amount").font(.headline)
                        Spacer()
                        Text("\(magnification, specifier: "%.1f")×").monospacedDigit()
                    }
                    Slider(value: $magnification, in: 1.3...2.5, step: 0.1).accessibilityLabel("Cursor zoom amount")
                    HStack {
                        Text("Subtle")
                        Spacer()
                        Text("Close-up")
                    }.font(.system(size: 11)).foregroundStyle(BlitzUI.secondaryText)
                }
            }
            if !edits.zoom.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Cursor zoom applied", systemImage: "checkmark.circle.fill").foregroundStyle(BlitzUI.mint)
                    Spacer()
                    Button("Remove zoom") {
                        var updated = edits
                        updated.zoom = .empty
                        apply(.init(edits: updated, actionName: "Remove Zoom"))
                    }
                }.font(.system(size: 12))
            }
        }
    }

    private struct EmptyStateRequest {
        let symbol: String
        let title: String
        let detail: String
    }
    private func emptyState(_ request: EmptyStateRequest) -> some View {
        VStack(spacing: 10) {
            Image(systemName: request.symbol).font(.system(size: 26, weight: .light)).foregroundStyle(
                BlitzUI.secondaryText)
            Text(request.title).font(.system(size: 13, weight: .semibold))
            Text(request.detail).font(.system(size: 11)).foregroundStyle(BlitzUI.secondaryText)
                .multilineTextAlignment(.center).frame(maxWidth: 340)
        }.frame(maxWidth: .infinity).padding(.vertical, 26)
            .background(BlitzUI.cardFill, in: .rect(cornerRadius: 12))
    }

    private struct TimeFieldRequest {
        let label: String
        let value: Binding<Double>
    }
    private func timeField(_ request: TimeFieldRequest) -> some View {
        HStack(spacing: 8) {
            Text(request.label).font(.system(size: 11)).foregroundStyle(BlitzUI.secondaryText)
            TextField("Seconds", value: request.value, format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.plain).font(.system(size: 12, weight: .medium, design: .monospaced))
                .frame(width: 58).accessibilityLabel("\(request.label) seconds")
            Text("s").font(.system(size: 10)).foregroundStyle(BlitzUI.secondaryText)
        }.padding(10).background(BlitzUI.cardFill, in: .rect(cornerRadius: 8))
    }

    private func durationLabel(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = max(0, seconds)
        return String(format: "%d:%04.1f", Int(total) / 60, total.truncatingRemainder(dividingBy: 60))
    }

    private func preview(_ time: Double) { playback.play(from: time) }

    @discardableResult
    private func apply(_ request: EditorTimelineEditsChange) -> Bool {
        let map = TimelineTimeMap(
            takeDuration: TimelineTimeMap.time(playback.duration), cuts: request.edits.enabledCuts)
        guard map.outputDuration.seconds >= 0.1 else {
            message = "Keep at least a moment of the recording."
            messageIsError = true
            return false
        }
        playback.pauseForEditing()
        guard vm.applyTimelineEdits(request) else {
            message = vm.detailMessage
            messageIsError = true
            return false
        }
        message = nil
        messageIsError = false
        return true
    }

    private func saveText() {
        var updated = edits
        let existing = updated.textOverlays.first { $0.id == editingTextID }
        let preservesStyle = existing?.style.preset == preset
        if let editingTextID { updated.textOverlays.removeAll { $0.id == editingTextID } }
        updated.textOverlays.append(
            .init(
                id: editingTextID ?? UUID(), start: start, end: end,
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                frame: preservesStyle ? existing!.frame : TextOverlay.defaultFrame(for: preset),
                style: preservesStyle ? existing!.style : .preset(preset)))
        guard apply(.init(edits: updated, actionName: editingTextID == nil ? "Add Text" : "Edit Text")) else { return }
        text = ""
        editingTextID = nil
    }

    private func generateZoom() {
        guard let project = vm.lastExportedProject, let cursorTrack else { return }
        var updated = edits
        updated.zoom = CursorZoomPlanning.plan(
            .init(
                samples: cursorTrack.samples, duration: playback.duration,
                trimOffset: project.timelineTrimOffsetSeconds, cuts: edits.enabledCuts, magnification: magnification))
        guard apply(.init(edits: updated, actionName: "Follow Cursor")) else { return }
        message =
            updated.zoom.isEmpty
            ? "No usable clicks remain after your cuts." : "Cursor zoom saved. Preview before exporting."
    }

}

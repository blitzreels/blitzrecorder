import SwiftUI

enum ScreenZoomStrength: Double, CaseIterable, Hashable {
    case subtle = 1.4
    case medium = 1.7
    case strong = 2.2

    var title: String {
        switch self {
        case .subtle: "Subtle"
        case .medium: "Medium"
        case .strong: "Strong"
        }
    }

    static func nearest(_ magnification: Double) -> ScreenZoomStrength {
        allCases.min { abs($0.rawValue - magnification) < abs($1.rawValue - magnification) } ?? .medium
    }
}

struct EditorZoomPointInspector: View {
    struct Configuration {
        let vm: RecorderViewModel
        let playback: EditorPlaybackController
        let point: ScreenZoomKeyframe
        let selection: Binding<UUID?>
    }

    let configuration: Configuration
    @State private var error: String?

    private enum Level: Hashable {
        case none
        case zoomed(ScreenZoomStrength)

        var title: String {
            switch self {
            case .none: "None"
            case .zoomed(let strength): strength.title
            }
        }

        var amount: Double {
            switch self {
            case .none: 0
            case .zoomed(let strength): ScreenZoomTrack.amount(forMagnification: strength.rawValue)
            }
        }
    }

    private var level: Level {
        configuration.point.amount < 0.001 ? .none
            : .zoomed(.nearest(ScreenZoomTrack.magnification(forAmount: configuration.point.amount)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            EditorInspectorRow(configuration: .init(title: "At") {
                BlitzTimeStepper(configuration: .init(
                    title: "Zoom point time", value: configuration.point.time,
                    range: 0...max(0, configuration.playback.duration), step: 0.1,
                    onCommit: { setTime($0) }
                ))
                Spacer(minLength: 0)
            })
            EditorInspectorRow(configuration: .init(title: "Zoom") {
                BlitzSegmentedPicker(configuration: .init(
                    title: "Zoom at this point",
                    options: [Level.none] + ScreenZoomStrength.allCases.map(Level.zoomed),
                    selection: Binding(get: { level }, set: { setLevel($0) }),
                    label: \.title
                ))
                .controlSize(.small)
            })
            Button(role: .destructive, action: remove) { Label("Remove point", systemImage: "trash") }
                .blitzButton(.quiet).controlSize(.small)
            if let error { Text(error).font(BlitzType.caption).foregroundStyle(BlitzUI.warning) }
        }
    }

    private func setTime(_ seconds: Double) {
        edit(.init(actionName: "Move Zoom Point") { $0.time = seconds })
        configuration.playback.seek(to: seconds)
    }

    private func setLevel(_ level: Level) {
        let previous = configuration.point.amount
        edit(.init(actionName: "Change Zoom Point") { keyframe in
            keyframe.amount = level.amount
            guard previous > 0.001, level.amount > 0.001 else { return }
            let scale = previous / level.amount
            keyframe.position = CGPoint(x: min(1, max(-1, keyframe.position.x * scale)),
                                        y: min(1, max(-1, keyframe.position.y * scale)))
        })
    }

    private struct Edit {
        let actionName: String
        let change: (inout ScreenZoomKeyframe) -> Void
    }

    private func edit(_ request: Edit) {
        guard var edits = configuration.vm.lastExportedProject?.edits,
              let index = edits.zoom.keyframes.firstIndex(where: { $0.id == configuration.point.id }) else { return }
        request.change(&edits.zoom.keyframes[index])
        edits.zoom.keyframes.sort { $0.time < $1.time }
        configuration.playback.pauseForEditing()
        if configuration.vm.applyTimelineEdits(.init(edits: edits, actionName: request.actionName)) {
            error = nil
        } else { error = configuration.vm.detailMessage }
    }

    private func remove() {
        guard var edits = configuration.vm.lastExportedProject?.edits else { return }
        edits.zoom.keyframes.removeAll { $0.id == configuration.point.id }
        if configuration.vm.applyTimelineEdits(.init(edits: edits, actionName: "Remove Zoom Point")) {
            configuration.selection.wrappedValue = nil
        } else { error = configuration.vm.detailMessage }
    }
}

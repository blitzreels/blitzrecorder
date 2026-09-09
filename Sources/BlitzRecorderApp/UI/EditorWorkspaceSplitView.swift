import SwiftUI

struct EditorPaneSizing: Equatable {
    enum Pane {
        case inspector
        case timeline

        var defaultSize: Double { self == .inspector ? 360 : 430 }
        var minimum: Double { self == .inspector ? 312 : 180 }
        var maximum: Double { self == .inspector ? 640 : 600 }
        var previewMinimum: Double { self == .inspector ? 360 : 200 }
    }

    struct Request {
        let pane: Pane
        let preferred: Double
        let available: Double
    }

    static let dividerSize = BlitzPaneDivider.thickness
    let value: Double
    let bounds: ClosedRange<Double>

    static func resolve(_ request: Request) -> Self {
        let available = request.available.isFinite ? max(0, request.available - dividerSize) : 0
        let minimum = request.pane.minimum
        let previewMinimum = request.pane.previewMinimum
        let maximum = min(request.pane.maximum, max(0, available - previewMinimum))
        let upper: Double
        let lower: Double
        if available < minimum + previewMinimum {
            lower = available * minimum / (minimum + previewMinimum)
            upper = lower
        } else {
            lower = minimum
            upper = maximum
        }
        let preferred = request.preferred.isFinite ? request.preferred : request.pane.defaultSize
        return Self(value: min(upper, max(lower, preferred)), bounds: lower...upper)
    }
}

struct EditorWorkspaceSplitView<Preview: View, Inspector: View, Timeline: View>: View {
    @ViewBuilder let preview: () -> Preview
    @ViewBuilder let inspector: () -> Inspector
    @ViewBuilder let timeline: () -> Timeline

    @AppStorage("editor.inspectorWidth") private var savedInspectorWidth = EditorPaneSizing.Pane.inspector.defaultSize
    @AppStorage("editor.timelineHeight") private var savedTimelineHeight = EditorPaneSizing.Pane.timeline.defaultSize
    @State private var inspectorWidthDraft: Double?
    @State private var timelineHeightDraft: Double?

    var body: some View {
        GeometryReader { proxy in
            let inspectorSize = EditorPaneSizing.resolve(
                .init(
                    pane: .inspector, preferred: inspectorWidthDraft ?? savedInspectorWidth, available: proxy.size.width
                ))
            let timelineSize = EditorPaneSizing.resolve(
                .init(
                    pane: .timeline, preferred: timelineHeightDraft ?? savedTimelineHeight, available: proxy.size.height
                ))
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    preview()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                    BlitzPaneDivider(
                        configuration: .init(
                            axis: .horizontal,
                            label: "Inspector width",
                            value: Binding(get: { inspectorSize.value }, set: { inspectorWidthDraft = $0 }),
                            bounds: inspectorSize.bounds,
                            defaultValue: EditorPaneSizing.Pane.inspector.defaultSize,
                            onCommit: {
                                savedInspectorWidth = inspectorWidthDraft ?? inspectorSize.value
                                inspectorWidthDraft = nil
                            }
                        ))
                    inspector()
                        .frame(width: inspectorSize.value)
                        .frame(maxHeight: .infinity)
                        .clipped()
                }
                .frame(height: max(0, proxy.size.height - timelineSize.value - EditorPaneSizing.dividerSize))
                BlitzPaneDivider(
                    configuration: .init(
                        axis: .vertical,
                        label: "Timeline height",
                        value: Binding(get: { timelineSize.value }, set: { timelineHeightDraft = $0 }),
                        bounds: timelineSize.bounds,
                        defaultValue: EditorPaneSizing.Pane.timeline.defaultSize,
                        onCommit: {
                            savedTimelineHeight = timelineHeightDraft ?? timelineSize.value
                            timelineHeightDraft = nil
                        }
                    ))
                timeline()
                    .frame(height: timelineSize.value)
                    .clipped()
            }
        }
    }
}

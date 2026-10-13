import SwiftUI

struct EditorPaneSizing: Equatable {
    enum Pane {
        case inspector
        case timeline
        case recorderInspector

        var defaultSize: Double {
            switch self {
            case .inspector: 420
            case .timeline: 380
            case .recorderInspector: 384
            }
        }

        var minimum: Double {
            switch self {
            case .inspector: 372
            case .timeline: 180
            case .recorderInspector: 336
            }
        }

        var maximum: Double {
            switch self {
            case .inspector: 700
            case .timeline: 600
            case .recorderInspector: 524
            }
        }

        var previewMinimum: Double {
            switch self {
            case .inspector: 360
            case .timeline: 200
            case .recorderInspector: 620
            }
        }
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
    let showsSourceTracks: Bool
    @ViewBuilder let preview: () -> Preview
    @ViewBuilder let inspector: () -> Inspector
    @ViewBuilder let timeline: () -> Timeline

    @AppStorage("editor.inspectorWidth") private var savedInspectorWidth = EditorPaneSizing.Pane.inspector.defaultSize
    @AppStorage("editor.timelineHeight") private var savedTimelineHeight = 430.0
    @AppStorage("editor.compactTimelineHeight") private var savedCompactTimelineHeight = EditorPaneSizing.Pane.timeline.defaultSize
    @State private var inspectorWidthDraft: Double?
    @State private var timelineHeightDraft: Double?

    var body: some View {
        GeometryReader { proxy in
            let inspectorSize = EditorPaneSizing.resolve(
                .init(
                    pane: .inspector,
                    preferred: inspectorWidthDraft ?? savedInspectorWidth,
                    available: proxy.size.width
                ))
            let timelineSize = EditorPaneSizing.resolve(
                .init(
                    pane: .timeline,
                    preferred: timelineHeightDraft ?? (showsSourceTracks ? savedTimelineHeight : savedCompactTimelineHeight),
                    available: proxy.size.height
                ))
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    preview()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                    BlitzPaneDivider(configuration: .init(
                        axis: .horizontal, paneSide: .trailing, label: "Inspector width",
                        value: Binding(get: { inspectorSize.value }, set: { inspectorWidthDraft = $0 }),
                        bounds: inspectorSize.bounds, defaultValue: EditorPaneSizing.Pane.inspector.defaultSize,
                        onCommit: {
                            savedInspectorWidth = inspectorWidthDraft ?? inspectorSize.value
                            inspectorWidthDraft = nil
                        }
                    ))
                    inspector().frame(width: inspectorSize.value).frame(maxHeight: .infinity).clipped()
                }
                .frame(height: max(0, proxy.size.height - timelineSize.value - EditorPaneSizing.dividerSize))
                BlitzPaneDivider(
                    configuration: .init(
                        axis: .vertical,
                        paneSide: .trailing,
                        label: "Timeline height",
                        value: Binding(get: { timelineSize.value }, set: { timelineHeightDraft = $0 }),
                        bounds: timelineSize.bounds,
                        defaultValue: showsSourceTracks ? 430 : EditorPaneSizing.Pane.timeline.defaultSize,
                        onCommit: {
                            let height = timelineHeightDraft ?? timelineSize.value
                            if showsSourceTracks { savedTimelineHeight = height }
                            else { savedCompactTimelineHeight = height }
                            timelineHeightDraft = nil
                        }
                    ))
                timeline()
                    .frame(height: timelineSize.value)
                    .clipped()
            }
        }
        .onChange(of: showsSourceTracks) { timelineHeightDraft = nil }
    }
}

struct RecorderInspectorSplitView<Stage: View, Inspector: View>: View {
    @ViewBuilder let stage: () -> Stage
    @ViewBuilder let inspector: () -> Inspector

    @AppStorage("recorder.inspectorWidth") private var savedInspectorWidth = EditorPaneSizing.Pane.recorderInspector.defaultSize
    @State private var inspectorWidthDraft: Double?

    var body: some View {
        GeometryReader { proxy in
            let inspectorSize = EditorPaneSizing.resolve(.init(
                pane: .recorderInspector,
                preferred: inspectorWidthDraft ?? savedInspectorWidth,
                available: proxy.size.width
            ))
            HStack(spacing: 0) {
                stage()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                BlitzPaneDivider(configuration: .init(
                    axis: .horizontal,
                    paneSide: .trailing,
                    label: "Inspector width",
                    value: Binding(get: { inspectorSize.value }, set: { inspectorWidthDraft = $0 }),
                    bounds: inspectorSize.bounds,
                    defaultValue: EditorPaneSizing.Pane.recorderInspector.defaultSize,
                    onCommit: {
                        savedInspectorWidth = inspectorWidthDraft ?? inspectorSize.value
                        inspectorWidthDraft = nil
                    }
                ))
                inspector()
                    .frame(width: inspectorSize.value)
                    .frame(maxHeight: .infinity)
            }
        }
    }
}

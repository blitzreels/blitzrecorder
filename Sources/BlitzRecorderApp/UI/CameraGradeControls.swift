import AppKit
import CoreImage
import SwiftUI
import UniformTypeIdentifiers

struct CameraGradeControls: View {
    struct Configuration {
        let savedGrade: CameraColorGrade
        let source: CGImage?
        let resetTitle: String
        let onPreview: (CameraColorGrade) -> Void
        let onCommit: (CameraColorGrade) -> Bool
    }

    private enum Comparison: String, CaseIterable {
        case before = "Before"
        case after = "After"
    }

    let configuration: Configuration

    @State private var draft: CameraColorGrade?
    @State private var lutError: String?
    @State private var comparison = Comparison.after

    private var savedGrade: CameraColorGrade { configuration.savedGrade }
    private var grade: CameraColorGrade { draft ?? savedGrade }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            looks
            light
            color
            profile
            if !grade.isNeutral {
                Button(configuration.resetTitle) { commit(.neutral) }
                    .blitzButton(.quiet)
                    .controlSize(.small)
                    .help("Back to the original picture for this camera")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await CameraColorLookLibrary.shared.preload() }
        .onChange(of: comparison) { updatePreview() }
        .onChange(of: savedGrade) {
            if draft == savedGrade { draft = nil }
            updatePreview()
        }
    }

    private var selectedLook: CameraColorLook? {
        grade.lut?.lookID.flatMap(CameraColorLook.look(id:))
    }

    private var lookTip: String {
        if let selectedLook { return selectedLook.tip }
        if let lut = grade.lut { return "Your LUT, \(lut.name). Use Strength to blend it with the original." }
        return "Your camera's picture. Pick a look, then set how strong it is."
    }

    private var looks: some View {
        EditorInspectorSection(configuration: .init(title: "Looks") {
            BlitzSegmentedPicker(configuration: .init(
                title: "Compare camera color",
                options: Comparison.allCases,
                selection: $comparison,
                label: { $0.rawValue }
            ))
            .controlSize(.small)
            .help("Compare the original camera and your grade in the main preview")
            slider(.init(title: "Strength", path: \.lutStrength, range: 0...1, label: Self.unitPercent))
                .disabled(grade.lut == nil)
            Text(lookTip)
                .font(BlitzType.caption)
                .foregroundStyle(BlitzUI.secondaryText)
                .lineLimit(2, reservesSpace: true)
            ForEach(CameraColorLook.Group.allCases, id: \.self) { group in
                Text(group.rawValue)
                    .font(BlitzType.captionEmphasis)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .padding(.top, 4)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    if group == .clean { originalChoice }
                    ForEach(CameraColorLook.all.filter { $0.group == group }) { look in
                        BlitzVisualChoice(configuration: .init(
                            title: look.title,
                            help: look.tip,
                            previewShape: .widescreen,
                            isSelected: grade.lut?.lookID == look.id,
                            action: {
                                if let updated = look.applying(to: grade) { commit(updated) }
                            },
                            preview: { thumbnail(look: look) }
                        ))
                    }
                }
            }
        })
    }

    private var originalChoice: some View {
        BlitzVisualChoice(configuration: .init(
            title: "Original",
            help: "Remove the look from this camera",
            previewShape: .widescreen,
            isSelected: grade.lut == nil,
            action: {
                var updated = grade
                updated.lut = nil
                commit(updated)
            },
            preview: { thumbnail(look: nil) }
        ))
    }

    private func thumbnail(look: CameraColorLook?) -> some View {
        CameraLookThumbnail(request: .init(
            source: configuration.source, sourceLook: grade.sourceLook, look: look
        ))
    }

    private var light: some View {
        EditorInspectorSection(configuration: .init(title: "Light") {
            slider(.init(title: "Exposure", path: \.exposure, range: -2...2, label: { String(format: "%+.1f", $0) }))
            slider(.init(title: "Contrast", path: \.contrast, range: -1...1, label: Self.percent))
        })
    }

    private var color: some View {
        EditorInspectorSection(configuration: .init(title: "Color") {
            slider(.init(title: "Saturation", path: \.saturation, range: -1...1, label: Self.percent))
            slider(.init(title: "Warmth", path: \.warmth, range: -1...1, label: Self.percent))
            slider(.init(title: "Tint", path: \.tint, range: -1...1, label: Self.percent))
        })
    }

    private var profileTip: String {
        grade.sourceLook == .djiDLog
            ? "D-Log M is a different curve. For it, get DJI's official LUT and import it."
            : "Leave on Normal video unless your footage looks flat and gray."
    }

    private var profile: some View {
        EditorInspectorSection(configuration: .init(title: "Camera profile & LUT") {
            BlitzDropdown(configuration: .init(
                title: "Filmed in",
                selection: Binding(
                    get: { grade.sourceLook },
                    set: { look in
                        var updated = grade
                        updated.sourceLook = look
                        commit(updated)
                    }
                ),
                options: CameraSourceLook.allCases.map { .init(value: $0, title: $0.title, detail: nil) }
            ))
            .help("Turns flat Log footage into normal color, using the formula its maker publishes")
            Text(profileTip)
                .font(BlitzType.caption)
                .foregroundStyle(BlitzUI.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let lut = grade.lut, lut.lookID == nil {
                HStack(spacing: 8) {
                    Text(lut.name)
                        .font(BlitzType.label)
                        .foregroundStyle(BlitzUI.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Button("Remove") {
                        var updated = grade
                        updated.lut = nil
                        commit(updated)
                    }
                    .blitzButton(.quiet)
                    .controlSize(.small)
                }
            }
            HStack(spacing: 8) {
                Button("Import LUT…", action: importLUT)
                    .blitzButton(.secondary)
                    .controlSize(.small)
                    .help("Use any 3D .cube file")
                Button("Get DJI LUTs") {
                    if let url = URL(string: "https://www.dji.com/lut") { NSWorkspace.shared.open(url) }
                }
                .blitzButton(.quiet)
                .controlSize(.small)
                .help("Open DJI's official LUT page. Download yours, then import it here")
            }
            if let lutError {
                Text(lutError)
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        })
    }

    private struct SliderRequest {
        let title: String
        let path: WritableKeyPath<CameraColorGrade, Double>
        let range: ClosedRange<Double>
        let label: (Double) -> String
    }

    private func slider(_ request: SliderRequest) -> some View {
        BlitzInspectorSlider(configuration: .init(
            title: request.title,
            value: Binding(
                get: { grade[keyPath: request.path] },
                set: { value in
                    var updated = grade
                    updated[keyPath: request.path] = value
                    comparison = .after
                    draft = updated
                    configuration.onPreview(updated)
                }
            ),
            range: request.range,
            step: 0.01,
            valueLabel: request.label(grade[keyPath: request.path]),
            onEditingChanged: { isEditing in
                if !isEditing, let draft { commit(draft) }
            },
            onReset: {
                var updated = grade
                updated[keyPath: request.path] = request.path == \.lutStrength ? selectedLook?.strength ?? 1 : 0
                commit(updated)
            }
        ))
    }

    private func updatePreview() {
        configuration.onPreview(comparison == .before ? .neutral : grade)
    }

    private func commit(_ updated: CameraColorGrade) {
        comparison = .after
        guard updated != savedGrade else {
            draft = nil
            configuration.onPreview(savedGrade)
            return
        }
        draft = updated
        configuration.onPreview(updated)
        if !configuration.onCommit(updated) {
            draft = nil
            configuration.onPreview(savedGrade)
        }
    }

    private func importLUT() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "cube") ?? .data]
        panel.allowsMultipleSelection = false
        panel.prompt = "Use LUT"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var updated = grade
            updated.lut = try CubeLUTFile.load(url: url)
            lutError = nil
            commit(updated)
        } catch {
            lutError = error.localizedDescription
        }
    }

    private static func percent(_ value: Double) -> String { String(format: "%+.0f", value * 100) }
    private static func unitPercent(_ value: Double) -> String { String(format: "%.0f%%", value * 100) }
}

private extension CameraColorGrade {
    var lutStrength: Double {
        get { lut?.strength ?? 1 }
        set { lut?.strength = newValue }
    }
}

private struct CameraLookThumbnail: View {
    struct Request: Equatable {
        let source: CGImage?
        let sourceLook: CameraSourceLook
        let look: CameraColorLook?

        static func == (lhs: Request, rhs: Request) -> Bool {
            lhs.source === rhs.source && lhs.sourceLook == rhs.sourceLook && lhs.look?.id == rhs.look?.id
        }
    }

    let request: Request
    @State private var image: CGImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                BlitzUI.cardFill
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
            }
        }
        .task(id: request) {
            guard let source = request.source else {
                image = nil
                return
            }
            let result = await CameraLookRenderer.shared.render(.init(
                source: source, sourceLook: request.sourceLook, look: request.look
            ))
            guard !Task.isCancelled else { return }
            image = result
        }
    }
}

private actor CameraLookRenderer {
    struct Request {
        let source: CGImage
        let sourceLook: CameraSourceLook
        let look: CameraColorLook?
    }

    static let shared = CameraLookRenderer()
    private let context = CIContext()

    func render(_ request: Request) -> CGImage? {
        var grade = CameraColorGrade.neutral
        grade.sourceLook = request.sourceLook
        if let look = request.look { grade = look.applying(to: grade) ?? grade }
        let source = CIImage(cgImage: request.source)
        return context.createCGImage(grade.applied(to: grade.cameraInput(from: source)), from: source.extent)
    }
}

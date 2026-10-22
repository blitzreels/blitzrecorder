import BlitzRecorderCore
import SwiftUI

struct CameraImageControlsConfiguration {
    let contentMode: Binding<CameraContentMode>
    let cropZoom: Binding<Double>
    let isCropModeEnabled: Bool
    let showsContentMode: Bool
    let isResetDisabled: Bool
    /// The editor puts Reset in the section header instead.
    let showsResetButton: Bool
    let onCropZoomEditingChanged: (Bool) -> Void
    let onBeginCrop: () -> Void
    let onResetCrop: () -> Void
}

struct CameraImageControls: View {
    let configuration: CameraImageControlsConfiguration

    private var mint: Color { BlitzUI.accent }

    var body: some View {
        if configuration.isCropModeEnabled {
            cropActiveNotice
        } else {
            cameraImageGroup
        }
    }

    private var cameraImageGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            if configuration.showsContentMode {
                SourceFramingPicker(selection: configuration.contentMode)
            }

            BlitzInspectorSlider(configuration: .init(
                title: "Zoom",
                value: configuration.cropZoom,
                range: 0...0.75,
                step: 0.01,
                valueLabel: EditorSourceZoom.label(configuration.cropZoom.wrappedValue),
                onEditingChanged: configuration.onCropZoomEditingChanged,
                onReset: configuration.onResetCrop
            ))
            .help("Zoom into the camera image and fill its frame")

            cropActions
        }
    }

    private var cropActiveNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "crop")
                .font(BlitzType.glyph(11))
                .foregroundStyle(mint)
            Text("Drag to crop. Done fills the camera frame.")
                .font(BlitzType.captionEmphasis)
                .foregroundStyle(BlitzUI.supportingText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(mint.opacity(0.12), in: .rect(cornerRadius: BlitzUI.controlRadius))
    }

    private var cropActions: some View {
        HStack(spacing: 8) {
            Button(action: configuration.onBeginCrop) {
                Label("Crop", systemImage: "crop")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .blitzButton(.secondary)
            .help("Choose the area that fills the camera frame. Done applies it; Cancel keeps the current framing.")

            if configuration.showsResetButton {
            Button(action: configuration.onResetCrop) {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .blitzButton(.secondary)
            .disabled(configuration.isResetDisabled)
            .accessibilityLabel("Reset camera zoom")
            .help("Reset zoom and position")
            }
        }
    }
}

struct CameraCropControls: View {
    @Bindable var vm: RecorderViewModel

    private var disabled: Bool {
        !vm.isSourceConfigured(.camera) || !vm.canEditCameraCrop
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if vm.isRemoteCameraSelected && !vm.canvas.isCameraCropModeEnabled {
                RemoteCameraOrientationControl(vm: vm)
            }

            CameraImageControls(configuration: cameraImageConfiguration)
        }
        .disabled(disabled)
        .opacity(disabled ? 0.6 : 1)
    }

    private var cameraImageConfiguration: CameraImageControlsConfiguration {
        CameraImageControlsConfiguration(
            contentMode: contentModeSelection,
            cropZoom: Binding(
                get: { cropZoom },
                set: { vm.setCameraCropZoom(CGFloat($0)) }
            ),
            isCropModeEnabled: vm.canvas.isCameraCropModeEnabled,
            showsContentMode: !vm.isCameraInsetLayout,
            isResetDisabled: isCentered,
            showsResetButton: true,
            onCropZoomEditingChanged: { _ in },
            onBeginCrop: vm.beginCameraCropMode,
            onResetCrop: vm.resetCameraCrop
        )
    }

    private var contentModeSelection: Binding<CameraContentMode> {
        Binding(
            get: { vm.settings.cameraContentMode },
            set: { vm.setCameraContentMode($0) }
        )
    }

    private var isCentered: Bool {
        vm.settings.cameraCropAmount.x < 0.001 && vm.settings.cameraCropAmount.y < 0.001
            && abs(vm.settings.cameraCropPosition.x) < 0.001 && abs(vm.settings.cameraCropPosition.y) < 0.001
    }

    private var cropZoom: Double {
        Double(max(vm.settings.cameraCropAmount.x, vm.settings.cameraCropAmount.y))
    }
}

struct CameraInsetFrameControlsConfiguration {
    let alignment: Binding<CameraInsetAlignment>
    let shape: Binding<CameraInsetShape>
    let size: Binding<Double>
    let sizeRange: ClosedRange<Double>
}

struct CameraInsetFrameControlPanel: View {
    let configuration: CameraInsetFrameControlsConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CameraDiagramRow(
                title: "Placement",
                options: CameraInsetAlignment.allCases,
                selection: configuration.alignment,
                label: { $0.displayName },
                draw: positionDraw
            )
            .help("Place the camera in the bottom left or bottom right corner")

            VStack(alignment: .leading, spacing: 8) {
                CameraDiagramRow(
                    title: "Frame",
                    options: CameraInsetShape.allCases,
                    selection: configuration.shape,
                    label: { $0.displayName },
                    draw: shapeDraw
                )
                .help("Camera frame shape")

                BlitzInspectorSlider(configuration: .init(
                    title: "Size",
                    value: configuration.size,
                    range: configuration.sizeRange,
                    step: 0.005,
                    valueLabel: "\(Int((configuration.size.wrappedValue * 100).rounded()))%",
                    onEditingChanged: { _ in },
                    onReset: {}
                ))
                .help("Camera frame size — the frame keeps the camera's real aspect ratio")
            }
        }
    }
}

struct CameraInsetFrameControls: View {
    @Bindable var vm: RecorderViewModel

    private var disabled: Bool {
        !vm.isSourceConfigured(.camera) || !vm.canEditScene
    }

    var body: some View {
        CameraInsetFrameControlPanel(configuration: configuration)
        .disabled(disabled)
        .opacity(disabled ? 0.6 : 1)
    }

    private var configuration: CameraInsetFrameControlsConfiguration {
        CameraInsetFrameControlsConfiguration(
            alignment: alignmentSelection,
            shape: shapeSelection,
            size: Binding(
                get: { vm.cameraInsetSize },
                set: { vm.setCameraInsetSize($0) }
            ),
            sizeRange: vm.cameraInsetSizeRange
        )
    }

    private var alignmentSelection: Binding<CameraInsetAlignment> {
        Binding(
            get: { vm.cameraInsetAlignment },
            set: { vm.setCameraInsetAlignment($0) }
        )
    }

    private var shapeSelection: Binding<CameraInsetShape> {
        Binding(
            get: { vm.cameraInsetShape },
            set: { vm.setCameraInsetShape($0) }
        )
    }
}

struct CameraDiagramPicker<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    let draw: (Value, inout GraphicsContext, CGSize, Bool) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { value in
                let isSelected = value == selection
                Button {
                    selection = value
                } label: {
                    VStack(spacing: 4) {
                        Canvas { ctx, size in
                            var c = ctx
                            draw(value, &c, size, isSelected)
                        }
                        .frame(width: 28, height: 28)

                        Text(label(value))
                            .font(BlitzType.footnote)
                            .foregroundStyle(isSelected ? BlitzUI.primaryText : BlitzUI.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .contentShape(.rect)
                }
                .buttonStyle(BlitzSelectionButtonStyle(isSelected: isSelected))
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .blitzTabGroup()
    }
}

struct CameraDiagramRow<Value: Hashable>: View {
    let title: String
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    let draw: (Value, inout GraphicsContext, CGSize, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            BlitzUI.sectionLabel(title)
            CameraDiagramPicker(
                options: options,
                selection: $selection,
                label: label,
                draw: draw
            )
        }
    }
}

private enum CamDiagram {
    static func canvasRect(_ s: CGSize) -> CGRect {
        let h = s.height - 8
        let w = h * 9 / 16
        return CGRect(x: (s.width - w) / 2, y: (s.height - h) / 2, width: w, height: h)
    }

    static func stroke(_ c: GraphicsContext, _ r: CGRect, _ rad: CGFloat, _ color: Color, _ lw: CGFloat = 1) {
        c.stroke(Path(roundedRect: r, cornerRadius: rad), with: .color(color), lineWidth: lw)
    }

    static func fill(_ c: GraphicsContext, _ r: CGRect, _ rad: CGFloat, _ color: Color) {
        c.fill(Path(roundedRect: r, cornerRadius: rad), with: .color(color))
    }
}

private func positionDraw(_ v: CameraInsetAlignment, _ c: inout GraphicsContext, _ s: CGSize, _ sel: Bool) {
    let f = CamDiagram.canvasRect(s)
    CamDiagram.fill(c, f, 3, BlitzUI.quietFill)
    CamDiagram.stroke(c, f, 3, (sel ? BlitzUI.tertiaryText : BlitzUI.strongStroke))
    let cw = f.width * 0.62, ch = cw * 9 / 16, pad: CGFloat = 2
    let x = (v == .bottomLeft) ? f.minX + pad : f.maxX - pad - cw
    let chip = CGRect(x: x, y: f.maxY - pad - ch, width: cw, height: ch)
    CamDiagram.fill(c, chip, 2, sel ? BlitzUI.accent : BlitzUI.tertiaryText)
}

private func shapeDraw(_ v: CameraInsetShape, _ c: inout GraphicsContext, _ s: CGSize, _ sel: Bool) {
    let f = CamDiagram.canvasRect(s)
    CamDiagram.fill(c, f, 3, BlitzUI.quietFill)
    CamDiagram.stroke(c, f, 3, BlitzUI.strongStroke)
    let pad: CGFloat = 2
    let w: CGFloat, h: CGFloat, radius: CGFloat
    switch v {
    case .landscape:
        w = f.width * 0.78
        h = w * 9 / 16
        radius = 2
    case .portrait:
        h = f.height * 0.5
        w = h * 9 / 16
        radius = 2
    case .circle:
        w = f.width * 0.66
        h = w
        radius = w / 2
    }
    let chip = CGRect(x: f.midX - w / 2, y: f.maxY - pad - h, width: w, height: h)
    CamDiagram.fill(c, chip, radius, sel ? BlitzUI.accent : BlitzUI.tertiaryText)
}

struct SourceFramingPicker: View {
    @Binding var selection: CameraContentMode

    var body: some View {
        BlitzSegmentedPicker(configuration: .init(
            title: "Source framing",
            options: CameraContentMode.allCases,
            selection: $selection,
            label: { $0 == .fill ? "Fill" : "Fit" },
            help: { $0 == .fill
                ? "Fill the frame, cropping the source edges."
                : "Keep the entire source visible without cropping." }
        ))
    }
}

#Preview("Camera diagram tiles") {
    struct DiagramPreview: View {
        @State private var alignment: CameraInsetAlignment = .bottomRight
        @State private var shape: CameraInsetShape = .landscape

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                CameraDiagramRow(
                    title: "Placement",
                    options: CameraInsetAlignment.allCases,
                    selection: $alignment,
                    label: { $0.displayName },
                    draw: positionDraw
                )
                CameraDiagramRow(
                    title: "Frame",
                    options: CameraInsetShape.allCases,
                    selection: $shape,
                    label: { $0.displayName },
                    draw: shapeDraw
                )
            }
            .padding(16)
            .frame(width: 268)
            .background(BlitzUI.canvasBackground)
        }
    }
    return DiagramPreview().preferredColorScheme(.dark)
}

#Preview("Source framing states") {
    VStack(alignment: .leading, spacing: 16) {
        SourceFramingPicker(selection: .constant(.fill))
        SourceFramingPicker(selection: .constant(.fit))
        SourceFramingPicker(selection: .constant(.fill))
            .disabled(true)
    }
    .padding(16)
    .frame(width: 280)
    .background(BlitzUI.canvasBackground)
    .preferredColorScheme(.dark)
}

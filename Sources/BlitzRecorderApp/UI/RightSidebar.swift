import BlitzRecorderCore
import SwiftUI

struct CameraImageControlsConfiguration {
    let contentMode: Binding<CameraContentMode>
    let cropZoom: Binding<Double>
    let isCropModeEnabled: Bool
    let showsContentMode: Bool
    let isResetDisabled: Bool
    let onCropZoomEditingChanged: (Bool) -> Void
    let onBeginCrop: () -> Void
    let onResetCrop: () -> Void
}

struct CameraImageControls: View {
    let configuration: CameraImageControlsConfiguration

    private let mint = BlitzUI.mint

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
                valueLabel: "\(Int((configuration.cropZoom.wrappedValue / 0.75 * 100).rounded()))%",
                onEditingChanged: configuration.onCropZoomEditingChanged,
                onReset: configuration.onResetCrop
            ))
            .help("Zoom into the camera image")

            cropActions
        }
    }

    private var cropActiveNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "crop")
                .font(BlitzType.glyph(11))
                .foregroundStyle(mint)
            Text("Drag on the preview to crop")
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
                Label("Crop on preview", systemImage: "crop")
                    .frame(maxWidth: .infinity)
            }
            .blitzButton(.secondary)
            .pointingHandCursor()
            .help("Drag the camera image on the preview to choose what shows")

            Button(action: configuration.onResetCrop) {
                Label("Reset zoom", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .blitzButton(.secondary)
            .disabled(configuration.isResetDisabled)
            .pointingHandCursor()
            .accessibilityLabel("Reset camera zoom")
            .help("Reset zoom and position")
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
            if vm.isRemoteCameraSelected && !vm.isCameraCropModeEnabled {
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
            isCropModeEnabled: vm.isCameraCropModeEnabled,
            showsContentMode: !vm.isCameraInsetLayout,
            isResetDisabled: isCentered,
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
                icon: "rectangle.inset.bottomleft.filled",
                options: CameraInsetAlignment.allCases,
                selection: configuration.alignment,
                label: { $0.displayName },
                draw: positionDraw
            )
            .help("Place the camera in the bottom left or bottom right corner")

            VStack(alignment: .leading, spacing: 8) {
                CameraDiagramRow(
                    title: "Frame",
                    icon: "rectangle.portrait",
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
                .pointingHandCursor()
            }
        }
        .blitzTabGroup()
    }
}

struct CameraDiagramRow<Value: Hashable>: View {
    let title: String
    let icon: String
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    let draw: (Value, inout GraphicsContext, CGSize, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(BlitzType.captionEmphasis)
                .foregroundStyle(BlitzUI.secondaryText)
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
    CamDiagram.fill(c, chip, 2, sel ? BlitzUI.mint : BlitzUI.tertiaryText)
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
    CamDiagram.fill(c, chip, radius, sel ? BlitzUI.mint : BlitzUI.tertiaryText)
}

struct SourceFramingPicker: View {
    @Binding var selection: CameraContentMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(CameraContentMode.allCases, id: \.self) { mode in
                BlitzTab(configuration: .init(
                    title: mode == .fill ? "Fill" : "Fit",
                    symbolName: nil,
                    isSelected: selection == mode,
                    expands: true,
                    action: { selection = mode }
                ))
                .help(mode == .fill
                    ? "Fill the frame, cropping the source edges."
                    : "Keep the entire source visible without cropping.")
            }
        }
        .blitzTabGroup()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Source framing")
    }
}

struct RemoteCameraOrientationControl: View {
    @Bindable var vm: RecorderViewModel
    var usesPanelBackground = false

    private var rotationDegrees: Int {
        RemoteCameraSettings.normalizedRotationDegrees(vm.selectedRemoteCameraRotationDegrees)
    }

    private var supportedRotationDegrees: [Int] {
        let supported = vm.selectedRemoteCameraSupportedRotationDegrees
        let canonical = [0, 90, 180, 270].filter { supported.contains($0) }
        return canonical.isEmpty ? [0, 90, 180, 270] : canonical
    }

    private var isEnabled: Bool {
        vm.isRemoteCameraSelected && vm.state == .idle && supportedRotationDegrees.count > 1
    }

    private var usesAutomaticRotation: Bool {
        vm.selectedRemoteCameraUsesAutomaticRotation
    }

    private var isPortraitRotation: Bool {
        RemoteCameraSettingsResolver.isPortraitRotation(rotationDegrees)
    }

    private var orientationLabel: String {
        let prefix = usesAutomaticRotation ? "Auto" : "Manual"
        return isPortraitRotation ? "\(prefix) Portrait" : "\(prefix) Landscape"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: isPortraitRotation ? "rectangle.portrait" : "rectangle")
                    .font(BlitzType.glyph(11))
                    .foregroundStyle(isEnabled ? BlitzUI.supportingText : BlitzUI.tertiaryText)
                    .frame(width: 18, height: 18)
                Text("Orientation")
                    .font(BlitzType.captionEmphasis)
                    .foregroundStyle(isEnabled ? BlitzUI.supportingText : BlitzUI.secondaryText)
                Spacer(minLength: 0)
                Text(orientationLabel)
                    .font(BlitzType.footnote)
                    .foregroundStyle(isEnabled ? BlitzUI.supportingText : BlitzUI.tertiaryText)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(BlitzUI.controlFill, in: .rect(cornerRadius: 6))
            }

            HStack(spacing: 7) {
                orientationButton("Auto", systemImage: "iphone.gen3") {
                    vm.setRemoteCameraAutomaticRotation(true)
                }
                .background(usesAutomaticRotation ? BlitzUI.mint.opacity(0.16) : Color.clear, in: .rect(cornerRadius: BlitzUI.controlRadius))
                orientationButton("Left", systemImage: "rotate.left") {
                    rotate(by: -1)
                }
                orientationButton("Right", systemImage: "rotate.right") {
                    rotate(by: 1)
                }
                orientationButton("Flip", systemImage: "arrow.up.and.down") {
                    flip()
                }
            }
        }
        .padding(usesPanelBackground ? 10 : 0)
        .background(usesPanelBackground ? BlitzUI.controlFill : Color.clear, in: .rect(cornerRadius: BlitzUI.cardRadius))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.6)
    }

    private func orientationButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(BlitzType.footnote)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, minHeight: 26)
        }
        .blitzButton(.secondary)
        .controlSize(.small)
        .pointingHandCursor()
        .help("\(title) iPhone feed")
    }

    private func rotate(by step: Int) {
        let next = nextRotation(step: step)
        vm.setRemoteCameraRotationDegrees(next)
    }

    private func flip() {
        let flipped = RemoteCameraSettings.normalizedRotationDegrees(rotationDegrees + 180)
        if supportedRotationDegrees.contains(flipped) {
            vm.setRemoteCameraRotationDegrees(flipped)
        } else {
            rotate(by: 2)
        }
    }

    private func nextRotation(step: Int) -> Int {
        let supported = supportedRotationDegrees
        guard !supported.isEmpty else { return rotationDegrees }
        let currentIndex = supported.firstIndex(of: rotationDegrees) ?? 0
        let nextIndex = (currentIndex + step % supported.count + supported.count) % supported.count
        return supported[nextIndex]
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
                    icon: "rectangle.inset.bottomleft.filled",
                    options: CameraInsetAlignment.allCases,
                    selection: $alignment,
                    label: { $0.displayName },
                    draw: positionDraw
                )
                CameraDiagramRow(
                    title: "Frame",
                    icon: "rectangle.portrait",
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

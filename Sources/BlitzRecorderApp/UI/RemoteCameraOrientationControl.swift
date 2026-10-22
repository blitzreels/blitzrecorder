import BlitzRecorderCore
import SwiftUI

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
                    .foregroundStyle(isEnabled ? BlitzUI.secondaryText : BlitzUI.tertiaryText)
            }

            HStack(spacing: 7) {
                orientationButton("Auto", systemImage: "iphone.gen3") {
                    vm.setRemoteCameraAutomaticRotation(true)
                }
                .background(usesAutomaticRotation ? BlitzUI.accent.opacity(0.16) : Color.clear, in: .rect(cornerRadius: BlitzUI.controlRadius))
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

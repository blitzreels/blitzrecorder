import SwiftUI

struct BlitzToggleStyle: ToggleStyle {
    enum Presentation {
        case switchRow
        case switchOnly
        case checkbox
    }

    let presentation: Presentation
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 10) {
                if presentation == .checkbox {
                    checkbox(isOn: configuration.isOn)
                }
                if presentation != .switchOnly {
                    configuration.label
                        .font(.system(size: BlitzControlMetrics.fontSize(controlSize), weight: .medium))
                        .foregroundStyle(BlitzUI.primaryText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if presentation == .switchRow {
                    Spacer(minLength: 12)
                }
                if presentation != .checkbox {
                    switchTrack(isOn: configuration.isOn)
                }
            }
            .padding(.vertical, 4)
            .frame(minHeight: max(28, BlitzControlMetrics.height(controlSize)))
            .contentShape(.rect(cornerRadius: BlitzControlMetrics.radius))
            .background(
                isEnabled && isHovering ? BlitzUI.quietFill : .clear,
                in: .rect(cornerRadius: BlitzControlMetrics.radius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: BlitzControlMetrics.radius)
                    .strokeBorder(isFocused && isEnabled ? BlitzUI.mint : .clear, lineWidth: 2)
                    .padding(-3)
                    .allowsHitTesting(false)
            }
        }
        .buttonStyle(BlitzPressButtonStyle())
        .focused($isFocused)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: configuration.isOn)
        .accessibilityRepresentation {
            if presentation == .checkbox {
                Toggle(isOn: configuration.$isOn) {
                    configuration.label.accessibilityElement(children: .combine)
                }
                    .toggleStyle(.checkbox)
                    .disabled(!isEnabled)
            } else {
                Toggle(isOn: configuration.$isOn) {
                    configuration.label.accessibilityElement(children: .combine)
                }
                    .toggleStyle(.switch)
                    .disabled(!isEnabled)
            }
        }
    }

    private func switchTrack(isOn: Bool) -> some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? BlitzUI.mint : BlitzUI.controlFill)
            Capsule()
                .strokeBorder(isOn ? .clear : outline, lineWidth: 1)
            HStack {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.black.opacity(0.72))
                    .opacity(isOn ? 1 : 0)
                Spacer(minLength: 0)
            }
            .padding(.leading, 6)
            Circle()
                .fill(isOn ? Color.white : Color.white.opacity(0.78))
                .frame(width: 16, height: 16)
                .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
                .padding(3)
        }
        .frame(width: 38, height: 22)
        .fixedSize()
    }

    private func checkbox(isOn: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(isOn ? BlitzUI.mint : BlitzUI.controlFill)
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(isOn ? .clear : outline, lineWidth: 1)
            }
            .overlay {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.black.opacity(0.88))
                    .opacity(isOn ? 1 : 0)
            }
            .frame(width: 18, height: 18)
            .fixedSize()
    }

    private var outline: Color {
        .white.opacity(contrast == .increased ? 0.65 : (isEnabled && isHovering ? 0.32 : 0.18))
    }
}

extension ToggleStyle where Self == BlitzToggleStyle {
    static var blitzSwitch: BlitzToggleStyle { .init(presentation: .switchRow) }
    static var blitzSwitchOnly: BlitzToggleStyle { .init(presentation: .switchOnly) }
    static var blitzCheckbox: BlitzToggleStyle { .init(presentation: .checkbox) }
}

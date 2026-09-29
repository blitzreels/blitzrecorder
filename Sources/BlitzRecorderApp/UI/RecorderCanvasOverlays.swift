import SwiftUI

struct RecordingCountdownOverlay: View {
    struct Configuration {
        let remaining: Int
        let onCancel: () -> Void
    }

    let configuration: Configuration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
            VStack(spacing: 16) {
                Text("\(configuration.remaining)")
                    .font(BlitzType.countdown)
                    .foregroundStyle(BlitzUI.primaryText)
                    .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
                    .animation(reduceMotion ? nil : .snappy, value: configuration.remaining)
                    .accessibilityLabel("Recording starts in \(configuration.remaining)")
                Button(action: configuration.onCancel) {
                    Label("Cancel", systemImage: "xmark")
                }
                .blitzButton(.secondary)
                .keyboardShortcut(.cancelAction)
                .help("Cancel the countdown (Esc)")
            }
        }
        .transition(.opacity)
    }
}

enum ShortFormSafeZone {
    static let preferenceKey = "recording.safeZones.visible"
    static let insets = EdgeInsets(top: 0.10, leading: 0.05, bottom: 0.22, trailing: 0.14)
}

struct ShortFormSafeZoneOverlay: View {
    @Bindable var vm: RecorderViewModel
    @AppStorage(ShortFormSafeZone.preferenceKey) private var isVisible = false

    var body: some View {
        GeometryReader { proxy in
            if isVisible, vm.settings.layout == .vertical, !vm.previewCanvasFrame.isEmpty {
                let canvas = CGRect(
                    x: vm.previewCanvasFrame.minX,
                    y: proxy.size.height - vm.previewCanvasFrame.maxY,
                    width: vm.previewCanvasFrame.width,
                    height: vm.previewCanvasFrame.height
                )
                let insets = ShortFormSafeZone.insets
                let safe = CGRect(
                    x: canvas.minX + canvas.width * insets.leading,
                    y: canvas.minY + canvas.height * insets.top,
                    width: canvas.width * (1 - insets.leading - insets.trailing),
                    height: canvas.height * (1 - insets.top - insets.bottom)
                )
                ZStack(alignment: .topLeading) {
                    Path { path in
                        path.addRect(canvas)
                        path.addRect(safe)
                    }
                    .fill(Color.black.opacity(0.38), style: FillStyle(eoFill: true))

                    RoundedRectangle(cornerRadius: BlitzUI.controlRadius)
                        .strokeBorder(BlitzUI.supportingText, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .frame(width: safe.width, height: safe.height)
                        .offset(x: safe.minX, y: safe.minY)

                    Text("Captions and app buttons cover this area")
                        .font(BlitzType.captionEmphasis)
                        .foregroundStyle(BlitzUI.supportingText)
                        .multilineTextAlignment(.center)
                        .frame(width: canvas.width - 24)
                        .position(x: canvas.midX, y: safe.maxY + (canvas.maxY - safe.maxY) / 2)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

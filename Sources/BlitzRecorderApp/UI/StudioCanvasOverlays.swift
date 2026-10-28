import SwiftUI

struct CropToolbarOverlay: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        GeometryReader { proxy in
            if let frame = vm.canvas.cropToolbarFrame,
               vm.canvas.isScreenCropModeEnabled || vm.canvas.isCameraCropModeEnabled {
                CropFloatingToolbar(configuration: cropToolbarConfiguration)
                    .fixedSize()
                    .position(
                        x: frame.midX,
                        y: proxy.size.height - frame.midY
                    )
            }
        }
    }

    private var cropToolbarConfiguration: CropFloatingToolbarConfiguration {
        CropFloatingToolbarConfiguration(
            onDone: {
                if vm.canvas.isCameraCropModeEnabled {
                    vm.applyCameraCropMode()
                } else {
                    vm.applyScreenCropMode()
                }
            },
            onReset: {
                if vm.canvas.isCameraCropModeEnabled {
                    vm.resetCameraCrop(vm.canvas.cameraCropModeLayer)
                } else {
                    vm.resetScreenCropMode()
                }
            },
            onCancel: {
                if vm.canvas.isCameraCropModeEnabled {
                    vm.cancelCameraCropMode()
                } else {
                    vm.cancelScreenCropMode()
                }
            }
        )
    }
}

struct ScreenPickPromptOverlay: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        GeometryReader { proxy in
            if let frame = vm.canvas.screenLayerFrame, frame.width > 1, frame.height > 1 {
                ScreenPickPrompt(vm: vm)
                    .fixedSize()
                    .position(x: frame.midX, y: proxy.size.height - frame.midY)
            } else {
                ScreenPickPrompt(vm: vm)
                    .fixedSize()
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
    }
}

private struct ScreenPickPrompt: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        Button {
            vm.pickScreen()
        } label: {
            Label(vm.screenPickActionTitle, systemImage: "macwindow")
        }
        .blitzButton(.emphasized)
        .controlSize(.large)
        .shadow(color: BlitzUI.elevationShadow, radius: 12, y: 4)
        .help("Choose an app window and fit it to the current scene")
    }
}

struct CropFloatingToolbarConfiguration {
    let onDone: () -> Void
    let onReset: () -> Void
    let onCancel: () -> Void
}

struct CropFloatingToolbar: View {
    let configuration: CropFloatingToolbarConfiguration

    var body: some View {
        HStack(spacing: 8) {
            Button(action: configuration.onCancel) {
                Image(systemName: "xmark")
            }
            .blitzButton(.secondary)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Cancel")
            .help("Cancel (Esc)")

            Button(action: configuration.onReset) {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .blitzButton(.secondary)
            .help("Show the whole source again")

            Button(action: configuration.onDone) {
                Label("Done", systemImage: "checkmark")
            }
            .blitzButton(.accent)
            .keyboardShortcut(.defaultAction)
            .help("Keep this framing (Return)")
        }
        .padding(8)
        .background(.regularMaterial, in: .rect(cornerRadius: BlitzUI.cardRadius))
        .shadow(color: BlitzUI.elevationShadow, radius: 12, y: 4)
    }
}

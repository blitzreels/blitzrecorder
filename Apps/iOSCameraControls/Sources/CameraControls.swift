import SwiftUI
import WidgetKit

@main
struct CameraControls: WidgetBundle {
    var body: some Widget {
        OpenCameraControl()
    }
}

/// One press from Control Center, the Lock Screen or the Action button opens the camera for the Mac.
struct OpenCameraControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "dev.blitzreels.blitzrecorder.camera.open") {
            ControlWidgetButton(action: OpenCameraIntent()) {
                Label("BlitzRecorder Camera", systemImage: "iphone.rear.camera")
            }
        }
        .displayName("BlitzRecorder Camera")
        .description("Open the camera for BlitzRecorder on your Mac.")
    }
}

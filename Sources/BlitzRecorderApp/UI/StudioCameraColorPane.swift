import SwiftUI

struct StudioCameraColorPane: View {
    @Bindable var vm: RecorderViewModel
    @State private var sourceImage: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shows live and applies to new recordings. You can change it in the editor.")
                .font(BlitzType.caption)
                .foregroundStyle(BlitzUI.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            CameraGradeControls(configuration: .init(
                savedGrade: vm.settings.cameraGrade,
                source: sourceImage,
                resetTitle: "Reset camera color",
                onPreview: { vm.previewCameraGrade($0) },
                onCommit: {
                    vm.setCameraGrade($0)
                    return true
                }
            ))
        }
        .task {
            while !Task.isCancelled {
                if vm.state == .idle { vm.requestCameraStill { sourceImage = $0 } }
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .onDisappear { vm.previewCameraGrade(vm.settings.cameraGrade) }
    }
}

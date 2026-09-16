import Foundation

extension RecorderViewModel {
    func pickScreen() {
        pickAndEnableScreenSource()
    }

    func pickFullScreen() {
        Task {
            do {
                try await coordinator.pickFullScreenSource()
                syncSettings()
                selectLayer(.screen)
                screenCaptureAreaSelection = .fullDisplay
                detailMessage = "Full screen selected for this session."
            } catch {
                detailMessage = RecorderStudioLabels.screenPickerFailed(error)
            }
        }
    }

    func switchRecordedScreenContent() {
        Task {
            do {
                try await coordinator.pickScreenContent()
                syncSettings()
                selectLayer(.screen)
                detailMessage = "Recorded screen source changed."
            } catch {
                detailMessage = RecorderStudioLabels.screenPickerFailed(error)
            }
        }
    }

}

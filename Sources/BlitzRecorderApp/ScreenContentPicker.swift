import Foundation
import ScreenCaptureKit

enum ScreenContentPickerPresentationMode {
    case newSelection
    case updateActiveStream

    static func resolve(hasActiveStream: Bool) -> Self {
        hasActiveStream ? .updateActiveStream : .newSelection
    }
}

extension RecordingState {
    var allowsScreenContentPickerPresentation: Bool {
        switch self {
        case .idle, .recording, .paused:
            return true
        case .starting, .finishing:
            return false
        }
    }
}

enum ScreenContentPickerSelectionPolicy {
    case appWindow
    case fullScreen
    case anyScreenContent

    var allowedModes: SCContentSharingPickerMode {
        switch self {
        case .appWindow:
            return .singleWindow
        case .fullScreen:
            return .singleDisplay
        case .anyScreenContent:
            return [.singleDisplay, .singleWindow]
        }
    }

    var fallbackSourceKind: ScreenSourceBinding.Kind? {
        switch self {
        case .appWindow:
            return .window
        case .fullScreen:
            return .display
        case .anyScreenContent:
            return nil
        }
    }

    var shouldAutoFitPickedWindow: Bool {
        self == .appWindow
    }

    func accepts(_ kind: ScreenSourceBinding.Kind?) -> Bool {
        guard let kind else { return true }
        switch self {
        case .appWindow:
            return kind == .application || kind == .window
        case .fullScreen:
            return kind == .display
        case .anyScreenContent:
            return true
        }
    }
}

struct ScreenContentPickerRequest {
    let activeStream: SCStream?
    let selectionPolicy: ScreenContentPickerSelectionPolicy
}

struct PickScreenContentRequest {
    let activatesScreenSource: Bool
    let selectionPolicy: ScreenContentPickerSelectionPolicy

    static func enablingScreen(_ settings: RecordingSettings, activatesScreenSource: Bool) -> RecordingSettings {
        var settings = settings
        settings.screenCrop = nil
        if activatesScreenSource {
            settings.enabledSources.insert(.screen)
            settings.hiddenSources.remove(.screen)
        }
        return settings
    }

    static func finishing(
        _ settings: RecordingSettings,
        pickedAspectRatio: CGFloat,
        activatesScreenSource: Bool,
        isIdle: Bool
    ) -> RecordingSettings {
        var settings = settings
        settings.screenSourceAspectRatio = pickedAspectRatio
        if activatesScreenSource, isIdle {
            settings.screenContentMode = .fit
        }
        return settings
    }

    static func applied(
        to settings: RecordingSettings,
        activatesScreenSource: Bool,
        pickedAspectRatio: CGFloat,
        isIdle: Bool,
        selecting: (RecordingSettings) -> RecordingSettings
    ) -> RecordingSettings {
        finishing(
            selecting(enablingScreen(settings, activatesScreenSource: activatesScreenSource)),
            pickedAspectRatio: pickedAspectRatio,
            activatesScreenSource: activatesScreenSource,
            isIdle: isIdle
        )
    }

    static func updatesActiveCapture(_ state: RecordingState) -> Bool {
        state == .recording || state == .paused
    }

    static func persistAction(updatesActiveRecording: Bool) -> PersistAction {
        updatesActiveRecording ? .cutTimeline : .updateIfNeeded
    }

    enum PersistAction: Equatable {
        case cutTimeline
        case updateIfNeeded
    }
}

@MainActor
final class ScreenContentPicker: NSObject, @preconcurrency SCContentSharingPickerObserver {
    private var continuation: CheckedContinuation<SCContentFilter, Error>?

    func pick(_ request: ScreenContentPickerRequest) async throws -> SCContentFilter {
        guard continuation == nil else {
            throw RecorderError.screenSelectionInProgress
        }
        guard #available(macOS 14.0, *) else {
            throw RecorderError.screenCapturePermissionRequired
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let picker = SCContentSharingPicker.shared
            var configuration = SCContentSharingPickerConfiguration()
            configuration.allowedPickerModes = request.selectionPolicy.allowedModes
            configuration.excludedBundleIDs = [Bundle.main.bundleIdentifier].compactMap { $0 }
            configuration.allowsChangingSelectedContent = true

            picker.configuration = configuration
            picker.maximumStreamCount = 1
            picker.isActive = true
            picker.add(self)
            switch ScreenContentPickerPresentationMode.resolve(hasActiveStream: request.activeStream != nil) {
            case .newSelection:
                picker.present()
            case .updateActiveStream:
                guard let activeStream = request.activeStream else {
                    picker.present()
                    return
                }
                picker.setConfiguration(configuration, for: activeStream)
                picker.present(for: activeStream)
            }
        }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        finish(picker: picker, result: .failure(RecorderError.screenSelectionCancelled))
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        finish(picker: picker, result: .success(filter))
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        finish(picker: SCContentSharingPicker.shared, result: .failure(error))
    }

    func cancel() {
        guard continuation != nil else { return }
        finish(
            picker: SCContentSharingPicker.shared,
            result: .failure(RecorderError.screenSelectionCancelled)
        )
    }

    private func finish(picker: SCContentSharingPicker, result: Result<SCContentFilter, Error>) {
        picker.remove(self)

        guard let continuation else { return }
        self.continuation = nil

        switch result {
        case .success(let filter):
            continuation.resume(returning: filter)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

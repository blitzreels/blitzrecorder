import Foundation
import ScreenCaptureKit

enum ScreenContentPickerPresentationMode {
    case newSelection
    case updateActiveStream

    static func resolve(hasActiveStream: Bool) -> Self {
        hasActiveStream ? .updateActiveStream : .newSelection
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
        picker.isActive = false

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

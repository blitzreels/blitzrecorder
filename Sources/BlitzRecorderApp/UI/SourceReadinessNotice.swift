import SwiftUI

struct SourceReadinessNotice: Equatable {
    struct Request {
        let source: CaptureSource
        let blockers: [PermissionBlocker]
    }

    enum Action {
        case chooseScreen
        case screenSettings
        case requestCamera
        case retryCamera
        case cameraSettings
        case requestMicrophone
        case microphoneSettings
        case manageDevices

        var title: String {
            switch self {
            case .chooseScreen: "Choose screen or window"
            case .screenSettings, .cameraSettings, .microphoneSettings: "Open System Settings"
            case .requestCamera: "Allow camera"
            case .retryCamera: "Retry camera"
            case .requestMicrophone: "Allow microphone"
            case .manageDevices: "Connect iPhone"
            }
        }

        /// The same action as a short button next to its problem.
        var shortTitle: String {
            switch self {
            case .chooseScreen: "Choose"
            case .screenSettings, .cameraSettings, .microphoneSettings: "Settings"
            case .requestCamera, .requestMicrophone: "Allow"
            case .retryCamera: "Retry"
            case .manageDevices: "Connect"
            }
        }
    }

    enum Severity {
        case warning
        case error
    }

    let title: String
    let detail: String
    let action: Action?
    let isWaiting: Bool
    let severity: Severity

    var color: Color { severity == .error ? BlitzUI.recordRed : BlitzUI.warning }

    static func resolve(_ request: Request) -> Self? {
        guard let blocker = request.blockers.first(where: { $0.source == request.source }) else { return nil }
        switch blocker.permission {
        case "Screen source":
            return .init(title: "No screen or window picked",
                detail: request.source == .systemAudio
                    ? "Choose a display or window to capture its audio."
                    : "Choose the display or window you want to record.",
                action: .chooseScreen, isWaiting: false, severity: .warning)
        case "Screen & System Audio Recording":
            return .init(title: "Allow Screen Recording",
                detail: request.source == .systemAudio
                    ? "macOS requires Screen Recording permission to record Mac audio."
                    : "Allow BlitzRecorder in macOS Screen Recording settings to capture this source.",
                action: .screenSettings, isWaiting: false, severity: .warning)
        case "Camera":
            return .init(title: "Camera permission needed", detail: blocker.recovery,
                action: blocker.status == "not determined" ? .requestCamera : .cameraSettings, isWaiting: false, severity: .warning)
        case "Microphone":
            return .init(title: "Microphone permission needed", detail: blocker.recovery,
                action: blocker.status == "not determined" ? .requestMicrophone : .microphoneSettings, isWaiting: false, severity: .warning)
        case "Camera availability" where blocker.status == "waiting":
            return .init(title: "Waiting for a camera", detail: blocker.recovery,
                action: nil, isWaiting: true, severity: .warning)
        case "Camera availability":
            let isStarting = blocker.status == "starting"
            return .init(title: isStarting ? "Starting camera" : "Camera unavailable",
                detail: isStarting ? "The camera preview is starting."
                    : "No camera video received. Reconnect your camera or iPhone, then retry. Close other apps using it.",
                action: isStarting ? nil : .retryCamera, isWaiting: isStarting, severity: .warning)
        case "Remote iPhone":
            return .init(title: "iPhone disconnected", detail: blocker.recovery,
                action: .manageDevices, isWaiting: false, severity: .warning)
        default:
            return .init(title: "Source unavailable", detail: blocker.recovery, action: nil, isWaiting: false, severity: .warning)
        }
    }
}

/// The microphone picked in Devices is saved as the preferred one; this is set while it is not connected.
struct MissingPreferredMicrophone: Equatable {
    let preferredName: String
    let fallbackName: String?

    var notice: SourceReadinessNotice {
        .init(title: "Preferred mic not connected",
              detail: fallbackName.map { "\(preferredName) is missing, so recording would use \($0). Connect it or choose another mic." }
                ?? "\(preferredName) is missing. Connect it to record sound.",
              action: nil, isWaiting: false, severity: .warning)
    }
}

extension RecorderViewModel {
    func sourceReadinessNotice(_ source: CaptureSource) -> SourceReadinessNotice? {
        if source == .screen, let notice = unavailableScreenSourceNotice { return notice }
        guard state == .idle, isSourceConfigured(source) else { return nil }
        if let notice = SourceReadinessNotice.resolve(.init(source: source, blockers: recordingReadiness.blockers)) {
            return notice
        }
        guard source == .microphone else { return nil }
        return iPhoneCompanionMicrophoneNotice ?? missingPreferredMicrophone?.notice
    }

    /// BlitzRecorder Camera needs its iPhone's microphone; the Mac taking it through Continuity stops the iPhone's
    /// take, so say so before recording instead of failing mid-take.
    var iPhoneCompanionMicrophoneNotice: SourceReadinessNotice? {
        guard isSourceConfigured(.microphone), MicrophoneDeviceSelection.usesIPhoneCompanion(settings) else { return nil }
        if MicrophoneDeviceSelection.conflictsWithIPhoneCompanion(settings: settings) {
            return .init(title: "This mic stops the iPhone camera",
                         detail: "The iPhone can't record while the Mac uses its microphone. Choose another microphone.",
                         action: nil, isWaiting: false, severity: .warning)
        }
        guard MicrophoneDeviceSelection.selectedMicrophone(settings: settings) == nil else { return nil }
        return .init(title: "No microphone",
                     detail: "The iPhone's microphone can't be used while it is the camera. Connect a microphone or mute it.",
                     action: nil, isWaiting: false, severity: .warning)
    }

    var missingPreferredMicrophone: MissingPreferredMicrophone? {
        guard isSourceConfigured(.microphone), let id = settings.selectedMicrophoneID,
              !availableMicrophones.contains(where: { $0.id == id }) else { return nil }
        return MissingPreferredMicrophone(
            preferredName: settings.selectedMicrophoneName ?? MicrophoneDeviceSelection.preferredName(id: id) ?? "Your preferred mic",
            fallbackName: availableMicrophones.isEmpty ? nil : selectedMicrophoneDisplayName
        )
    }

    func resolveSourceReadiness(_ action: SourceReadinessNotice.Action) {
        guard !isRequestingPermissions else { return }
        if action == .chooseScreen {
            guard canAdjustScreenCapture else { return }
            if isSourceConfigured(.screen) {
                showsScreenSourcePicker = true
            } else {
                pickScreen()
            }
            return
        }
        guard state == .idle else { return }
        switch action {
        case .chooseScreen: pickScreen()
        case .screenSettings: openScreenRecordingSettings()
        case .requestCamera: requestCameraAccessFromCover()
        case .retryCamera: onRetryCameraPreview?()
        case .cameraSettings: openCameraSettings()
        case .requestMicrophone: requestMicrophoneAccessFromCover()
        case .microphoneSettings: openMicrophoneSettings()
        case .manageDevices: showSettings(.devices)
        }
    }
}

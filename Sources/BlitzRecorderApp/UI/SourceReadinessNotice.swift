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
        case cameraSettings
        case requestMicrophone
        case microphoneSettings
        case manageDevices

        var title: String {
            switch self {
            case .chooseScreen: "Choose screen or window"
            case .screenSettings, .cameraSettings, .microphoneSettings: "Open System Settings"
            case .requestCamera: "Allow camera"
            case .requestMicrophone: "Allow microphone"
            case .manageDevices: "Connect iPhone"
            }
        }
    }

    let title: String
    let detail: String
    let action: Action?
    let isWaiting: Bool

    static func resolve(_ request: Request) -> Self? {
        guard let blocker = request.blockers.first(where: { $0.source == request.source }) else { return nil }
        switch blocker.permission {
        case "Screen source":
            return .init(title: "Choose screen or window",
                detail: request.source == .systemAudio
                    ? "Choose a display or window to capture its audio."
                    : "Choose the display or window you want to record.",
                action: .chooseScreen, isWaiting: false)
        case "Screen & System Audio Recording":
            return .init(title: "Allow Screen Recording",
                detail: request.source == .systemAudio
                    ? "macOS requires Screen Recording permission to record Mac audio."
                    : "Allow BlitzRecorder in macOS Screen Recording settings to capture this source.",
                action: .screenSettings, isWaiting: false)
        case "Camera":
            return .init(title: "Camera permission needed", detail: blocker.recovery,
                action: blocker.status == "not determined" ? .requestCamera : .cameraSettings, isWaiting: false)
        case "Microphone":
            return .init(title: "Microphone permission needed", detail: blocker.recovery,
                action: blocker.status == "not determined" ? .requestMicrophone : .microphoneSettings, isWaiting: false)
        case "Camera availability":
            let isStarting = blocker.status == "starting"
            return .init(title: isStarting ? "Starting camera" : "Camera unavailable",
                detail: isStarting ? "The camera preview is starting."
                    : "Choose another camera below, or close the app using this camera.",
                action: nil, isWaiting: isStarting)
        case "Remote iPhone":
            return .init(title: "iPhone disconnected", detail: blocker.recovery,
                action: .manageDevices, isWaiting: false)
        default:
            return .init(title: "Source unavailable", detail: blocker.recovery, action: nil, isWaiting: false)
        }
    }
}

extension RecorderViewModel {
    func sourceReadinessNotice(_ source: CaptureSource) -> SourceReadinessNotice? {
        guard state == .idle, isSourceConfigured(source) else { return nil }
        return SourceReadinessNotice.resolve(.init(source: source, blockers: recordingReadiness.blockers))
    }

    func resolveSourceReadiness(_ action: SourceReadinessNotice.Action) {
        guard state == .idle, !isRequestingPermissions else { return }
        switch action {
        case .chooseScreen: pickScreen()
        case .screenSettings: openScreenRecordingSettings()
        case .requestCamera: requestCameraAccessFromCover()
        case .cameraSettings: openCameraSettings()
        case .requestMicrophone: requestMicrophoneAccessFromCover()
        case .microphoneSettings: openMicrophoneSettings()
        case .manageDevices: showSettings(.devices)
        }
    }
}

struct SourceReadinessNoticeView: View {
    let notice: SourceReadinessNotice
    @Bindable var vm: RecorderViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if notice.isWaiting { ProgressView().controlSize(.mini) }
                Text(notice.title)
                    .font(BlitzType.label)
                    .foregroundStyle(notice.isWaiting ? BlitzUI.primaryText : BlitzUI.warning)
            }
            Text(notice.detail)
                .font(BlitzType.caption)
                .foregroundStyle(BlitzUI.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let action = notice.action {
                Button(action.title) { vm.resolveSourceReadiness(action) }
                    .blitzButton(.secondary)
                    .controlSize(.small)
                    .disabled(vm.isRequestingPermissions)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 6)
    }
}

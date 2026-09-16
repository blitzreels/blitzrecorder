import AppKit
import Foundation

extension RecorderViewModel {
    func dismissFirstRunOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.firstRunOnboardingKey)
        showsFirstRunOnboarding = false
    }

    func startFromCover() {
        dismissFirstRunOnboarding()
    }

    func requestScreenAccessFromCover() {
        Task {
            let result = await coordinator.permissionGate.requestScreenCaptureAccess()
            if result.status == .needsSettings {
                screenAccessAwaitingRestart = true
            }
            detailMessage = result.message
            refreshPermissionStatus()
            if result.status == .granted {
                await refreshSources()
            }
        }
    }

    func requestCameraAccessFromCover() {
        Task {
            _ = await coordinator.permissionGate.requestCameraAccess()
            syncSettings()
            refreshPermissionStatus()
        }
    }

    func requestMicrophoneAccessFromCover() {
        Task {
            _ = await coordinator.permissionGate.requestMicrophoneAccess()
            syncSettings()
            refreshPermissionStatus()
        }
    }

    func allowAllFromCover() {
        Task {
            let needsScreenGrant =
                (settings.enabledSources.contains(.screen)
                    && !settings.usesPickedScreenContent)
            if needsScreenGrant, !isPersistentScreenCaptureAccessActive {
                let result = await coordinator.permissionGate.requestScreenCaptureAccess()
                if result.status == .needsSettings {
                    screenAccessAwaitingRestart = true
                }
            }
            if settings.enabledSources.contains(.camera),
               !isRemoteCameraSelected {
                _ = await coordinator.permissionGate.requestCameraAccess()
            }
            if settings.enabledSources.contains(.microphone) {
                _ = await coordinator.permissionGate.requestMicrophoneAccess()
            }
            syncSettings()
            refreshPermissionStatus()
        }
    }

    func openCameraSettings() {
        coordinator.permissionGate.openCameraSettings()
    }

    func openMicrophoneSettings() {
        coordinator.permissionGate.openMicrophoneSettings()
    }

    func quitAndReopen() {
        let bundlePath = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; exec /usr/bin/open \"$1\"", "blitzrecorder-relaunch", bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }

    var screenNeedsPicking: Bool {
        RecordingStartGate.screenNeedsPicking(
            settings: settings,
            hasActiveSelection: coordinator.hasActiveScreenSourceSelection
        )
    }

    var screenPickActionTitle: String {
        "Choose App Window"
    }

    func pickAndEnableScreenSource() {
        Task {
            do {
                try await coordinator.pickScreenSource()
                syncSettings()
                selectLayer(.screen)
                if settings.usesPickedScreenContent, settings.screenSourceBinding != nil {
                    detailMessage = RecorderStudioLabels.screenSourceActivationMessage(
                        usesPickedScreenContent: true,
                        hasPersistentBinding: true
                    )
                } else {
                    detailMessage = RecorderStudioLabels.screenSourceActivationMessage(
                        usesPickedScreenContent: settings.usesPickedScreenContent,
                        hasPersistentBinding: false
                    )
                }
            } catch {
                detailMessage = RecorderStudioLabels.screenPickerFailed(error)
            }
        }
    }

    func pickAndEnableSystemAudioSource() {
        Task {
            do {
                try await coordinator.pickScreenContent()
                coordinator.addSource(.systemAudio)
                syncSettings()
                selectSource(.systemAudio)
                detailMessage = "Mac audio source selected for this session."
            } catch {
                detailMessage = RecorderStudioLabels.screenPickerFailed(error)
            }
        }
    }

    func applyScreenRecordingPermission() {
        Task {
            let result = await coordinator.permissionGate.requestScreenCaptureAccess()
            detailMessage = result.message
            refreshPermissionStatus()
            if result.status == .granted {
                await refreshSources()
            }
        }
    }

    func requestSourcePermissions() {
        Task {
            await coordinator.requestPermissionsForEnabledSources()
            syncSettings()
            let readiness = coordinator.recordingReadiness()
            detailMessage = readiness.isReady ? "Recording permissions ready." : readiness.detail
            refreshPermissionStatus()
        }
    }

    func runPrimaryPermissionAction() {
        switch PermissionPrimaryAction.resolve(blockers: recordingReadiness.blockers) {
        case .requestAccess:
            requestSourcePermissions()
        case .openSettings:
            openScreenRecordingSettings()
            detailMessage = recordingReadiness.blockers.first?.sentence
                ?? "Enable Screen Recording for BlitzRecorder, then quit and reopen it."
        case .checkAccess:
            refreshPermissionStatus()
        }
    }

    func requestAccessibilityPermission() {
        Task {
            let result = await coordinator.permissionGate.requestAccessibilityAccessForWindowControls()
            detailMessage = result.message
            refreshPermissionStatus()
        }
    }

    func refreshPermissionStatus(message: String? = nil) {
        if let message {
            detailMessage = message
        }
        permissionRefreshToken += 1
    }

    func openAccessibilitySettings() {
        coordinator.permissionGate.openAccessibilitySettings()
    }

    func selectScreenCrop() {
        beginScreenCropMode()
    }

    func clearScreenCrop() {
        cancelScreenCropMode()
        coordinator.clearScreenCrop()
        syncSettings()
        screenCaptureAreaSelection = .fullDisplay
    }

    func openScreenRecordingSettings() {
        coordinator.permissionGate.openScreenCaptureSettings()
    }


    var recordingReadiness: RecordingReadiness {
        _ = permissionRefreshToken
        return coordinator.recordingReadiness()
    }

    var permissionStatusRows: [PermissionStatusRow] {
        _ = permissionRefreshToken
        let readiness = recordingReadiness
        let hasPersistentScreenCaptureAccess = coordinator.hasScreenCaptureAccess()
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? "BlitzRecorder"
        let permissionGate = coordinator.permissionGate
        let currentSettings = settings
        return PermissionStatusRows.make(.init(
            settings: currentSettings,
            readiness: readiness,
            hasPersistentScreenCaptureAccess: hasPersistentScreenCaptureAccess,
            appName: appName,
            hasAccessibilityAccess: permissionGate.hasAccessibilityAccess,
            status: { source, isBlocked in
                switch source {
                case .screen:
                    return hasPersistentScreenCaptureAccess
                        ? "allowed for \(appName)"
                        : "not enabled for \(appName)"
                case .systemAudio:
                    return isBlocked
                        ? permissionGate.status(
                            PermissionGate.StatusRequest(source: source, settings: currentSettings)
                        )
                        : "enabled for recordings"
                case .camera, .microphone:
                    return permissionGate.status(
                        PermissionGate.StatusRequest(source: source, settings: currentSettings)
                    )
                }
            }
        ))
    }

    var permissionIssueCount: Int {
        recordingReadiness.blockers.count
    }

    var permissionSetupSummary: String {
        PermissionStatusRows.setupSummary(
            readiness: recordingReadiness,
            enabledSourcesEmpty: settings.enabledSources.isEmpty
        )
    }

    var primaryPermissionActionTitle: String {
        PermissionStatusRows.actionTitle(blockers: recordingReadiness.blockers)
    }

    var shouldSuggestScreenPicker: Bool {
        RecordingStartGate.shouldSuggestScreenPicker(readiness: recordingReadiness, settings: settings)
    }

    var isPersistentScreenCaptureAccessActive: Bool {
        coordinator.hasScreenCaptureAccess()
    }

    var shouldShowAppWindowSourcePermissionHint: Bool {
        false
    }

    var needsPersistentScreenCaptureAccess: Bool {
        false
    }

}

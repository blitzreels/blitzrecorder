import AppKit
import Foundation

extension RecorderViewModel {
    func startPermissionRequest(_ operation: @escaping @MainActor () async -> Void) {
        guard permissionRequestTask == nil else { return }
        let requestID = UUID()
        permissionRequestID = requestID
        isRequestingPermissions = true
        permissionRequestTask = Task { [weak self] in
            await operation()
            guard let self, permissionRequestID == requestID else { return }
            permissionRequestTask = nil
            permissionRequestID = nil
            isRequestingPermissions = false
        }
    }

    func cancelPendingPermissionRequests() {
        permissionRequestTask?.cancel()
        permissionRequestTask = nil
        permissionRequestID = nil
        isRequestingPermissions = false
    }

    func dismissFirstRunOnboarding() {
        cancelPendingPermissionRequests()
        UserDefaults.standard.set(true, forKey: Self.firstRunOnboardingKey)
        showsFirstRunOnboarding = false
    }

    func startFromCover() {
        dismissFirstRunOnboarding()
    }

    func requestScreenAccessFromCover() {
        startPermissionRequest { [weak self] in
            guard let self else { return }
            let result = await coordinator.permissionGate.requestScreenCaptureAccess()
            guard !Task.isCancelled, result.status != .cancelled else { return }
            detailMessage = result.message
            refreshPermissionStatus()
            if result.status == .granted {
                await refreshSources()
            }
        }
    }

    func enableSystemAudioFromCover() {
        coordinator.addSource(.systemAudio)
        syncSettings()
        requestScreenAccessFromCover()
    }

    func requestCameraAccessFromCover() {
        startPermissionRequest { [weak self] in
            guard let self else { return }
            _ = await coordinator.permissionGate.requestCameraAccess()
            guard !Task.isCancelled else { return }
            syncSettings()
            refreshPermissionStatus()
        }
    }

    func requestMicrophoneAccessFromCover() {
        startPermissionRequest { [weak self] in
            guard let self else { return }
            _ = await coordinator.permissionGate.requestMicrophoneAccess()
            guard !Task.isCancelled else { return }
            syncSettings()
            refreshPermissionStatus()
        }
    }

    func allowAllFromCover() {
        startPermissionRequest { [weak self] in
            guard let self else { return }
            let needsScreenGrant =
                (settings.enabledSources.contains(.screen)
                    && !settings.usesPickedScreenContent)
                    || settings.enabledSources.contains(.systemAudio)
            if needsScreenGrant, !isPersistentScreenCaptureAccessActive {
                let result = await coordinator.permissionGate.requestScreenCaptureAccess()
                guard !Task.isCancelled, result.status != .cancelled else { return }
                if result.status == .needsSettings {
                    detailMessage = result.message
                    refreshPermissionStatus()
                    return
                }
            }
            if settings.enabledSources.contains(.camera),
               !isRemoteCameraSelected {
                _ = await coordinator.permissionGate.requestCameraAccess()
                guard !Task.isCancelled else { return }
            }
            if settings.enabledSources.contains(.microphone) {
                _ = await coordinator.permissionGate.requestMicrophoneAccess()
                guard !Task.isCancelled else { return }
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
        cancelPendingPermissionRequests()
        let bundlePath = Bundle.main.bundlePath
        let processID = ProcessInfo.processInfo.processIdentifier
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; exec /usr/bin/open \"$2\"",
            "blitzrecorder-relaunch",
            String(processID),
            bundlePath
        ]
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
        "Choose app window"
    }

    func pickAndEnableScreenSource() {
        guard coordinator.hasScreenCaptureAccess() else {
            applyScreenRecordingPermission()
            return
        }
        if !isSourceConfigured(.screen) {
            coordinator.addSource(.screen)
            syncSettings()
        }
        selectSource(.screen)
        showsScreenSourcePicker = true
    }

    func pickAndEnableSystemAudioSource() {
        coordinator.addSource(.systemAudio)
        syncSettings()
        selectSource(.systemAudio)
        detailMessage = "Mac audio records through the screen source. Choose a screen or window."
        pickAndEnableScreenSource()
    }

    func applyScreenRecordingPermission() {
        startPermissionRequest { [weak self] in
            guard let self else { return }
            let result = await coordinator.permissionGate.requestScreenCaptureAccess()
            guard !Task.isCancelled, result.status != .cancelled else { return }
            detailMessage = result.message
            refreshPermissionStatus()
            if result.status == .granted {
                await refreshSources()
            }
        }
    }

    func requestSourcePermissions() {
        startPermissionRequest { [weak self] in
            guard let self else { return }
            await coordinator.requestPermissionsForEnabledSources()
            guard !Task.isCancelled else { return }
            syncSettings()
            let readiness = coordinator.recordingReadiness()
            if settings.enabledSources.contains(.systemAudio),
               !coordinator.permissionGate.hasScreenCaptureAccess {
                detailMessage = "Mac audio is off until Screen Recording access is enabled."
            } else {
                detailMessage = readiness.isReady ? "Recording permissions ready." : readiness.detail
            }
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
        startPermissionRequest { [weak self] in
            guard let self else { return }
            let result = await coordinator.permissionGate.requestAccessibilityAccessForWindowControls()
            guard !Task.isCancelled, result.status != .cancelled else { return }
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
        screenAccessAwaitingRestart = true
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
                    return permissionGate.status(
                        PermissionGate.StatusRequest(source: source, settings: currentSettings)
                    )
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

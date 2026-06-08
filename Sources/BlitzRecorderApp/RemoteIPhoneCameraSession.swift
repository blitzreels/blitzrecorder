import BlitzRecorderCore
import BlitzRecorderTransport
import CoreGraphics
import CoreMedia
import Foundation
import ImageIO

@MainActor
protocol RemoteIPhoneCameraBrowsing: AnyObject {
    var onStateChanged: (@Sendable (BonjourServiceState) -> Void)? { get set }
    var onServicesChanged: (@Sendable ([DiscoveredBonjourService]) -> Void)? { get set }

    func start()
}

@MainActor
protocol RemoteIPhoneCameraControlling: AnyObject {
    var connectedServiceID: String? { get }
    var isConnected: Bool { get }
    var onMessage: ((String) -> Void)? { get set }
    var onStateChanged: ((RemoteCameraConnectionState) -> Void)? { get set }
    var onEvent: ((RemoteCameraEvent) -> Void)? { get set }

    func connect(to service: DiscoveredBonjourService, forceReconnect: Bool)
    func send(_ command: RemoteCameraCommand)
    func pair(shortCode: String, challenge: RemoteCameraPairingChallenge)
    func disconnect()
}

extension BonjourServiceBrowser: RemoteIPhoneCameraBrowsing {}
extension RemoteCameraControlClient: RemoteIPhoneCameraControlling {}

@MainActor
final class RemoteIPhoneCameraSession {
    private let browser: RemoteIPhoneCameraBrowsing
    private let controlClient: RemoteIPhoneCameraControlling
    private lazy var runtime = RemoteCameraSessionRuntime(
        sendCommand: { [weak self] command in
            self?.controlClient.send(command)
        },
        onMessage: { [weak self] message in
            self?.onMessage?(message)
        }
    )

    private var sessionState = RemoteIPhoneCameraState()
    private var reconnectTasks: [String: Task<Void, Never>] = [:]
    private var settingsSendTasks: [String: Task<Void, Never>] = [:]
    private var previewSuppressedUntil: [String: Date] = [:]
    private var isDiscoveryStarted = false
    private let monitorSampleBufferFactory = RemoteCameraMonitorSampleBufferFactory()
    private let readSettings: () -> RecordingSettings
    private let saveSettings: (RecordingSettings) -> Void
    private let screenAspectRatio: () -> CGFloat
    private let canAttemptPendingImports: () -> Bool
    private let reconnectDelay: Duration
    private let settingsSendDelay: Duration

    var onMessage: ((String) -> Void)?
    var onCameraConfigurationChanged: (() -> Void)?
    var onPreviewFrame: ((CGImage) -> Void)?
    var onPreviewSampleBuffer: ((CMSampleBuffer, Int, Int) -> Void)?
    var onPreviewReset: ((String) -> Void)?
    var onPairingCodeRequested: ((String) -> String?)?

    init(
        readSettings: @escaping () -> RecordingSettings,
        saveSettings: @escaping (RecordingSettings) -> Void,
        screenAspectRatio: @escaping () -> CGFloat,
        canAttemptPendingImports: @escaping () -> Bool,
        browser: RemoteIPhoneCameraBrowsing? = nil,
        controlClient: RemoteIPhoneCameraControlling? = nil,
        reconnectDelay: Duration = .seconds(2),
        settingsSendDelay: Duration = .milliseconds(150)
    ) {
        self.readSettings = readSettings
        self.saveSettings = saveSettings
        self.screenAspectRatio = screenAspectRatio
        self.canAttemptPendingImports = canAttemptPendingImports
        self.browser = browser ?? BonjourServiceBrowser(serviceType: RemoteCameraConstants.bonjourServiceType)
        self.controlClient = controlClient ?? RemoteCameraControlClient()
        self.reconnectDelay = reconnectDelay
        self.settingsSendDelay = settingsSendDelay
        self.controlClient.onMessage = { [weak self] message in
            self?.onMessage?(message)
        }
    }

    var activeTakeID: UUID? {
        runtime.activeTakeID
    }

    func isRemoteCameraSelected() -> Bool {
        RemoteCameraProviderID.isRemote(readSettings().selectedCameraID)
    }

    func selectCamera(id: String?) {
        let currentSettings = readSettings()
        let isRetryingSelectedRemoteCamera = id == currentSettings.selectedCameraID
            && RemoteCameraProviderID.isRemote(id)
        var settings = currentSettings
        settings.selectedCameraID = id
        saveSettings(settings)

        if let serviceID = RemoteCameraProviderID.serviceID(from: id) {
            startDiscoveryIfNeeded()
            connect(serviceID: serviceID, forceReconnect: isRetryingSelectedRemoteCamera)
        } else {
            controlClient.disconnect()
        }
        onCameraConfigurationChanged?()
    }

    func connectDirect(host: String, portString: String) {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPort = portString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty,
              let port = UInt16(trimmedPort),
              port > 0 else {
            onMessage?("Enter the iPhone IP address and the port shown in the companion app.")
            return
        }

        let service = DiscoveredBonjourService.directTCP(host: trimmedHost, port: port)
        sessionState.upsertDirectService(service)
        var settings = readSettings()
        settings.selectedCameraID = RemoteCameraProviderID.make(for: service.id)
        saveSettings(settings)
        connect(serviceID: service.id)
        onCameraConfigurationChanged?()
    }

    func startDiscoveryIfNeeded() {
        guard !isDiscoveryStarted else { return }
        isDiscoveryStarted = true

        controlClient.onStateChanged = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self,
                      let serviceID = RemoteCameraProviderID.serviceID(from: self.readSettings().selectedCameraID) else {
                    return
                }
                self.sessionState.setConnectionState(state, for: serviceID)
                switch state {
                case .connected, .pairing:
                    self.reconnectTasks[serviceID]?.cancel()
                    self.reconnectTasks[serviceID] = nil
                case .disconnected, .degraded:
                    self.scheduleReconnect(serviceID: serviceID)
                default:
                    break
                }
                self.onCameraConfigurationChanged?()
            }
        }
        controlClient.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event)
            }
        }
        browser.onStateChanged = { [weak self] state in
            if case .failed(let message) = state {
                Task { @MainActor [weak self] in
                    self?.onMessage?("Remote iPhone discovery failed: \(message)")
                }
            }
        }
        browser.onServicesChanged = { [weak self] services in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let previousServiceIDs = self.sessionState.replaceDiscoveredServices(services)
                var settings = self.readSettings()
                if let selectedServiceID = RemoteCameraProviderID.serviceID(from: settings.selectedCameraID),
                   let service = self.bestMatchingService(for: selectedServiceID, services: services) {
                    if service.id != selectedServiceID {
                        settings.selectedCameraID = RemoteCameraProviderID.make(for: service.id)
                        self.saveSettings(settings)
                    }
                    let wasRediscovered = !previousServiceIDs.contains(service.id)
                    self.connect(serviceID: service.id, forceReconnect: wasRediscovered)
                } else if let service = self.sessionState.automaticSelection(settings: settings) {
                    settings.selectedCameraID = RemoteCameraProviderID.make(for: service.id)
                    self.saveSettings(settings)
                    self.connect(serviceID: service.id)
                }
                self.onCameraConfigurationChanged?()
            }
        }
        browser.start()
    }

    func requireConnection() async throws {
        let settings = readSettings()
        guard let selectedServiceID = RemoteCameraProviderID.serviceID(from: settings.selectedCameraID) else {
            throw RecorderError.remoteCameraNotConnected
        }
        if isConnected(serviceID: selectedServiceID) {
            return
        }

        if sessionState.containsService(id: selectedServiceID) {
            connect(serviceID: selectedServiceID, forceReconnect: true)
        }

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if isConnected(serviceID: selectedServiceID) {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        throw RecorderError.remoteCameraNotConnected
    }

    func connectionBlocker() -> PermissionBlocker? {
        let settings = readSettings()
        guard settings.enabledSources.contains(.camera),
              let selectedServiceID = RemoteCameraProviderID.serviceID(from: settings.selectedCameraID),
              !isConnected(serviceID: selectedServiceID) else {
            return nil
        }

        if sessionState.containsService(id: selectedServiceID),
           sessionState.connectionStates[selectedServiceID] != .pairing {
            scheduleReconnect(serviceID: selectedServiceID)
        }

        return PermissionBlocker(
            source: .camera,
            permission: "Remote iPhone",
            status: selectedStatus() ?? "not connected",
            recovery: "Keep the iPhone camera app open and wait for it to reconnect."
        )
    }

    func selectedName() -> String? {
        sessionState.selectedName(settings: readSettings())
    }

    func selectedStatus() -> String? {
        sessionState.selectedStatus(
            settings: readSettings(),
            previewHealthStatus: Self.previewHealthStatus
        )
    }

    func selectedConnectionState() -> RemoteCameraConnectionState? {
        guard let selectedServiceID = RemoteCameraProviderID.serviceID(from: readSettings().selectedCameraID) else {
            return nil
        }
        return sessionState.connectionState(for: selectedServiceID)
    }

    func selectedDeviceDescription() -> String {
        sessionState.selectedDeviceDescription(
            settings: readSettings(),
            marketingName: Self.iPhoneMarketingName
        )
    }

    func selectedCapabilities() -> RemoteCameraCapabilities? {
        sessionState.selectedCapabilities(
            settings: readSettings(),
            normalizedSettings: { [weak self] proposedSettings, serviceID in
                guard let self else { return proposedSettings }
                return self.normalizedSettings(proposedSettings, for: serviceID)
            }
        )
    }

    func selectedTelemetry() -> RemoteCameraTelemetry? {
        sessionState.selectedTelemetry(
            settings: readSettings(),
            normalizedSettings: { [weak self] proposedSettings, serviceID in
                guard let self else { return proposedSettings }
                return self.normalizedSettings(proposedSettings, for: serviceID)
            }
        )
    }

    func deviceSummaries() -> [RemoteCameraDeviceSummary] {
        sessionState.deviceSummaries(
            settings: readSettings(),
            marketingName: Self.iPhoneMarketingName,
            previewHealthStatus: Self.previewHealthStatus
        )
    }

    func cameraOptions() -> [SourceOption] {
        sessionState.cameraOptions()
    }

    func applySettingsIntent(_ intent: RemoteCameraSettingsIntent) {
        guard let selectedServiceID = RemoteCameraProviderID.serviceID(from: readSettings().selectedCameraID) else {
            return
        }
        let settings = readSettings()
        let result = RemoteCameraSettingsCommand.apply(
            intent,
            to: remoteSettings(for: selectedServiceID),
            capabilities: sessionState.capabilities[selectedServiceID],
            preferredFrameRate: settings.framesPerSecond
        )
        if let message = result.message {
            onMessage?(message)
        }
        guard result.didChange else { return }
        commitSettings(result.settings, serviceID: selectedServiceID)
    }

    func resetSettings() {
        guard let selectedServiceID = RemoteCameraProviderID.serviceID(from: readSettings().selectedCameraID) else {
            return
        }
        let settings = readSettings()
        let result = RemoteCameraSettingsCommand.apply(
            .resetAll(frameRate: settings.framesPerSecond),
            to: remoteSettings(for: selectedServiceID),
            capabilities: sessionState.capabilities[selectedServiceID],
            preferredFrameRate: settings.framesPerSecond
        )
        commitSettings(result.settings, serviceID: selectedServiceID, sendImmediately: true)
    }

    func sendSettings() {
        guard let selectedServiceID = RemoteCameraProviderID.serviceID(from: readSettings().selectedCameraID) else {
            return
        }
        settingsSendTasks[selectedServiceID]?.cancel()
        settingsSendTasks[selectedServiceID] = nil
        controlClient.send(.applySettings(remoteSettings(for: selectedServiceID)))
    }

    func currentCameraSourceAspectRatio(fallback: CGFloat = SceneLayout.cameraAspectRatio) -> CGFloat {
        currentCameraSourceAspectRatio(settings: readSettings(), fallback: fallback)
    }

    private func currentCameraSourceAspectRatio(
        settings: RecordingSettings,
        fallback: CGFloat = SceneLayout.cameraAspectRatio
    ) -> CGFloat {
        guard let selectedServiceID = RemoteCameraProviderID.serviceID(from: settings.selectedCameraID),
              let capabilities = sessionState.capabilities[selectedServiceID] else {
            return fallback
        }

        let remoteSettings = remoteSettings(for: selectedServiceID)
        let lensCapabilities = capabilities.capabilities(for: remoteSettings.lens)
        let selectableFormats = RemoteCameraSettingsResolver.formats(
            lensCapabilities.supportedFormats,
            supportedBy: remoteSettings.captureProfileID,
            profiles: lensCapabilities.supportedCaptureProfiles
        )
        let formatCandidates = selectableFormats.isEmpty ? lensCapabilities.supportedFormats : selectableFormats
        guard let format = formatCandidates.first(where: { $0.id == remoteSettings.formatID })
            ?? formatCandidates.first else {
            return fallback
        }

        return CGFloat(RemoteCameraSettingsResolver.aspectRatio(
            format: format,
            rotationDegrees: remoteSettings.rotationDegrees
        ))
    }

    func beginTake(takeID: UUID, take: RecordingTake) {
        runtime.beginTake(
            takeID: takeID,
            serviceID: RemoteCameraProviderID.serviceID(from: readSettings().selectedCameraID),
            take: take,
            settings: readSettings()
        )
    }

    func removePendingImport(takeID: UUID) {
        runtime.removePendingImport(takeID: takeID, settings: readSettings())
    }

    func cancelCommand() {
        runtime.cancelCommand()
    }

    func abandonTake(takeID: UUID) {
        runtime.abandonTake(takeID: takeID)
    }

    func markTimelineStart(takeID: UUID, hostTimelineStartTime: UInt64) {
        runtime.markTimelineStart(takeID: takeID, hostTimelineStartTime: hostTimelineStartTime)
    }

    func prepare(takeID: UUID, hostStartTime: UInt64) async throws -> UInt64 {
        try await runtime.prepare(takeID: takeID, hostStartTime: hostStartTime)
    }

    func start(takeID: UUID, hostStartTime: UInt64, hostTimelineStartTime: UInt64?) async throws -> UInt64 {
        try await runtime.start(
            takeID: takeID,
            hostStartTime: hostStartTime,
            hostTimelineStartTime: hostTimelineStartTime
        )
    }

    func stopAndImport(take: RecordingTake) async throws -> MediaWriterCompletion {
        try await runtime.stopAndImport(take: take, settings: readSettings())
    }

    func importFailureMessage(error: Error, take: RecordingTake) -> String {
        let reason = error.recorderFailureDescription
        let lowercasedReason = reason.lowercased()
        let failedBeforeSavingMedia = lowercasedReason.contains("failed before stop")
            || lowercasedReason.contains("empty file")
            || lowercasedReason.contains("while failed")

        if failedBeforeSavingMedia {
            return "Recording failed: iPhone camera did not save usable media: \(reason). "
                + "Screen/source files are in \(take.scratchDirectory.path)."
        }

        return "Recording failed: Remote iPhone import did not finish: \(reason). "
            + "The take is waiting for the iPhone master recording. Keep both devices on the same Wi-Fi, reopen BlitzRecorder Camera, then retry the pending import. Recovery files: \(take.scratchDirectory.path)"
    }

    private func bestMatchingService(
        for selectedServiceID: String,
        services: [DiscoveredBonjourService]
    ) -> DiscoveredBonjourService? {
        if let exactMatch = services.first(where: { $0.id == selectedServiceID }) {
            return exactMatch
        }
        let selectedName = selectedServiceID
            .split(separator: ".")
            .first
            .map(String.init)?
            .removingPercentEncoding
        if let selectedName,
           let nameMatch = services.first(where: { $0.name == selectedName }) {
            return nameMatch
        }
        return services.count == 1 ? services[0] : nil
    }

    private func connect(serviceID: String, forceReconnect: Bool = false) {
        guard let service = sessionState.service(id: serviceID) else {
            sessionState.setConnectionState(.discovering, for: serviceID)
            return
        }
        sessionState.setConnectionState(.pairing, for: serviceID)
        if forceReconnect || controlClient.connectedServiceID != serviceID {
            sessionState.clearSettingsRestoreMarker(for: serviceID)
        }
        controlClient.connect(to: service, forceReconnect: forceReconnect)
    }

    private func scheduleReconnect(serviceID: String) {
        let settings = readSettings()
        guard settings.selectedCameraID == RemoteCameraProviderID.make(for: serviceID),
              reconnectTasks[serviceID] == nil,
              sessionState.containsService(id: serviceID) else {
            return
        }
        reconnectTasks[serviceID] = Task { [weak self] in
            try? await Task.sleep(for: self?.reconnectDelay ?? .seconds(2))
            await MainActor.run { [weak self] in
                guard let self,
                      !Task.isCancelled,
                      self.readSettings().selectedCameraID == RemoteCameraProviderID.make(for: serviceID) else {
                    return
                }
                self.reconnectTasks[serviceID] = nil
                self.connect(serviceID: serviceID, forceReconnect: true)
            }
        }
    }

    private func isConnected(serviceID: String) -> Bool {
        sessionState.connectionStates[serviceID] == .connected
            && controlClient.connectedServiceID == serviceID
            && controlClient.isConnected
    }

    private func commitSettings(
        _ remoteSettings: RemoteCameraSettings,
        serviceID selectedServiceID: String,
        sendImmediately: Bool = false
    ) {
        var settings = readSettings()
        settings.remoteCameraSettingsByServiceID[selectedServiceID] = remoteSettings
        suppressPreview(serviceID: selectedServiceID, message: "Updating iPhone camera...")
        refreshSelectedScenePresetLayoutIfNeeded(settings: &settings)
        saveSettings(settings)
        sessionState.updateTelemetrySettings(for: selectedServiceID, activeSettings: remoteSettings)
        if sendImmediately {
            settingsSendTasks[selectedServiceID]?.cancel()
            settingsSendTasks[selectedServiceID] = nil
            controlClient.send(.applySettings(remoteSettings))
        } else {
            scheduleSettingsSend(remoteSettings, serviceID: selectedServiceID)
        }
        onCameraConfigurationChanged?()
    }

    private func refreshSelectedScenePresetLayoutIfNeeded(settings: inout RecordingSettings) {
        guard let preset = settings.selectedScenePreset,
              preset.supports(settings.layout) else {
            return
        }
        settings.sceneLayout = SceneLayout.presetLayout(
            preset,
            for: settings.layout,
            screenAspectRatio: screenAspectRatio(),
            cameraAspectRatio: currentCameraSourceAspectRatio(settings: settings)
        )
    }

    private func scheduleSettingsSend(_ remoteSettings: RemoteCameraSettings, serviceID: String) {
        settingsSendTasks[serviceID]?.cancel()
        settingsSendTasks[serviceID] = Task { [weak self] in
            try? await Task.sleep(for: self?.settingsSendDelay ?? .milliseconds(150))
            await MainActor.run { [weak self] in
                guard let self,
                      !Task.isCancelled,
                      self.readSettings().selectedCameraID == RemoteCameraProviderID.make(for: serviceID) else {
                    return
                }
                self.settingsSendTasks[serviceID] = nil
                self.controlClient.send(.applySettings(remoteSettings))
            }
        }
    }

    private func remoteSettings(for selectedServiceID: String) -> RemoteCameraSettings {
        let settings = readSettings()
        let activeTelemetry = sessionState.telemetry[selectedServiceID]
        return normalizedSettings(
            settings.remoteCameraSettingsByServiceID[selectedServiceID]
                ?? activeTelemetry?.activeSettings
                ?? RemoteCameraSettings(),
            for: selectedServiceID
        )
    }

    private func normalizedSettings(
        _ proposedSettings: RemoteCameraSettings,
        for selectedServiceID: String
    ) -> RemoteCameraSettings {
        RemoteCameraSettingsResolver.normalized(
            proposedSettings,
            capabilities: sessionState.capabilities[selectedServiceID],
            preferredFrameRate: readSettings().framesPerSecond
        )
    }

    private func mergeAutomaticRotationTelemetry(
        _ telemetry: RemoteCameraTelemetry,
        serviceID: String,
        settings: inout RecordingSettings
    ) -> (telemetry: RemoteCameraTelemetry, didUpdateSettings: Bool) {
        let hadSavedSettings = settings.remoteCameraSettingsByServiceID[serviceID] != nil
        var savedSettings = settings.remoteCameraSettingsByServiceID[serviceID] ?? telemetry.activeSettings
        guard savedSettings.usesAutomaticRotation,
              telemetry.activeSettings.usesAutomaticRotation else {
            return (telemetry, false)
        }
        guard telemetry.phase == .idle || telemetry.phase == .preparing else {
            return (telemetry, false)
        }

        let rotationDegrees = RemoteCameraSettings.normalizedRotationDegrees(telemetry.activeSettings.rotationDegrees)
        guard !hadSavedSettings || savedSettings.rotationDegrees != rotationDegrees else {
            return (telemetry, false)
        }

        savedSettings.rotationDegrees = rotationDegrees
        settings.remoteCameraSettingsByServiceID[serviceID] = savedSettings
        if settings.selectedScenePreset?.supports(settings.layout) == true {
            refreshSelectedScenePresetLayoutIfNeeded(settings: &settings)
        }

        var mergedTelemetry = telemetry
        mergedTelemetry.activeSettings = savedSettings
        return (mergedTelemetry, true)
    }

    private func suppressPreview(serviceID: String, message: String) {
        previewSuppressedUntil[serviceID] = Date().addingTimeInterval(1.25)
        onPreviewReset?(message)
    }

    private func isPreviewSuppressed(serviceID: String) -> Bool {
        guard let suppressedUntil = previewSuppressedUntil[serviceID] else {
            return false
        }
        if Date() < suppressedUntil {
            return true
        }
        previewSuppressedUntil.removeValue(forKey: serviceID)
        return false
    }

    private func handle(_ event: RemoteCameraEvent) {
        let settings = readSettings()
        guard let serviceID = RemoteCameraProviderID.serviceID(from: settings.selectedCameraID) else {
            return
        }
        switch event {
        case .pairingChallenge(let challenge):
            sessionState.setConnectionState(.pairing, for: serviceID)
            if !challenge.requiresShortCode {
                controlClient.pair(shortCode: "", challenge: challenge)
                onMessage?("Verifying trusted Remote iPhone Camera...")
                onCameraConfigurationChanged?()
                return
            }
            guard let code = requestPairingCode(for: challenge) else {
                controlClient.send(.cancel)
                onMessage?("Remote iPhone pairing cancelled.")
                onCameraConfigurationChanged?()
                return
            }
            controlClient.pair(shortCode: code, challenge: challenge)
            onMessage?("Pairing \(challenge.deviceName)...")
            onCameraConfigurationChanged?()
        case .paired(let trust):
            var settings = readSettings()
            settings.trustedRemoteCameraServiceIDs.insert(serviceID)
            saveSettings(settings)
            sessionState.setConnectionState(.connected, for: serviceID)
            onMessage?("Paired \(trust.deviceName) as Remote iPhone Camera.")
            controlClient.send(.requestCapabilities)
            attemptPendingImports(serviceID: serviceID)
            onCameraConfigurationChanged?()
        case .capabilities(let capabilities):
            sessionState.setCapabilities(capabilities, for: serviceID)
            sessionState.setConnectionState(.connected, for: serviceID)
            onMessage?("Remote iPhone ready: \(capabilities.supportedLenses.map(\.displayName).joined(separator: ", "))")
            var settings = readSettings()
            if settings.selectedCameraID == RemoteCameraProviderID.make(for: serviceID),
               settings.selectedScenePreset?.supports(settings.layout) == true {
                refreshSelectedScenePresetLayoutIfNeeded(settings: &settings)
                saveSettings(settings)
            }
            if settings.remoteCameraSettingsByServiceID[serviceID] != nil,
               !sessionState.hasSentSettingsRestore(for: serviceID) {
                let restoredSettings = remoteSettings(for: serviceID)
                sessionState.updateTelemetrySettings(for: serviceID, activeSettings: restoredSettings)
                sessionState.markSettingsRestoreSent(for: serviceID)
                suppressPreview(serviceID: serviceID, message: "Updating iPhone camera...")
                controlClient.send(.applySettings(restoredSettings))
            }
            attemptPendingImports(serviceID: serviceID)
            onCameraConfigurationChanged?()
        case .telemetry(let telemetry):
            var settings = readSettings()
            let mergeResult = mergeAutomaticRotationTelemetry(
                telemetry,
                serviceID: serviceID,
                settings: &settings
            )
            sessionState.setTelemetry(mergeResult.telemetry, for: serviceID)
            if mergeResult.didUpdateSettings {
                saveSettings(settings)
            }
            onCameraConfigurationChanged?()
        case .failed(let failedTakeID, let reason):
            sessionState.setConnectionState(.degraded, for: serviceID)
            onMessage?("Remote iPhone error: \(reason)")
            runtime.handleFailed(takeID: failedTakeID, reason: reason)
        case .transferReady(let takeID, _, let byteCount, let manifest):
            runtime.applyTransferReady(
                takeID: takeID,
                byteCount: byteCount,
                manifest: manifest,
                settings: readSettings()
            )
            onCameraConfigurationChanged?()
        case .monitorFrame(let jpegData, _, _):
            guard !isPreviewSuppressed(serviceID: serviceID) else { return }
            if let image = Self.makeCGImage(fromJPEGData: jpegData) {
                onPreviewFrame?(image)
            }
        case .monitorVideoFrame(let frame):
            guard !isPreviewSuppressed(serviceID: serviceID) else { return }
            if let sampleBuffer = monitorSampleBufferFactory.makeSampleBuffer(from: frame) {
                onPreviewSampleBuffer?(sampleBuffer, frame.width, frame.height)
            }
        case .transferChunk(let takeID, let offset, let data, let isFinal):
            runtime.writeChunk(takeID: takeID, offset: offset, data: data, isFinal: isFinal)
            onCameraConfigurationChanged?()
        case .transferComplete(let takeID, let byteCount, let sha256):
            Task { @MainActor in
                await runtime.completeTransfer(
                    takeID: takeID,
                    byteCount: byteCount,
                    sha256: sha256,
                    settings: readSettings()
                )
                onCameraConfigurationChanged?()
            }
        case .prepared(let takeID, let deviceStartTime):
            runtime.resolvePrepared(takeID: takeID, deviceStartTime: deviceStartTime)
            onCameraConfigurationChanged?()
        case .started(let takeID, let deviceStartTime):
            runtime.resolveStarted(takeID: takeID, deviceStartTime: deviceStartTime)
            onCameraConfigurationChanged?()
        case .stopped(_, _, _, let reason):
            if let reason, !reason.isEmpty {
                onMessage?("Remote iPhone stopped recording: \(reason)")
            }
            onCameraConfigurationChanged?()
        }
    }

    private func attemptPendingImports(serviceID: String) {
        guard canAttemptPendingImports() else { return }
        runtime.requestPendingImports(serviceID: serviceID, settings: readSettings())
    }

    private func requestPairingCode(for challenge: RemoteCameraPairingChallenge) -> String? {
        guard let rawCode = onPairingCodeRequested?(challenge.deviceName) else {
            return nil
        }
        let code = RemoteCameraPairingCode.normalized(rawCode)
        return RemoteCameraPairingCode.isValid(code) ? code : nil
    }

    private static func previewHealthStatus(_ health: RemoteCameraPreviewHealth) -> String {
        if health.isTransferActive {
            return "Importing iPhone video"
        }
        guard health.framesSent > 0 else {
            return "Waiting for live view"
        }
        if health.isStale {
            return "Live view stalled"
        }
        if health.isBlockedBeforeFirstFrame {
            return "Live view blocked"
        }
        if health.isDroppingFrames {
            return "iPhone live view is dropping frames"
        }
        return "iPhone connected"
    }

    private static func makeCGImage(fromJPEGData data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func iPhoneMarketingName(for identifier: String?) -> String? {
        guard let identifier else { return nil }
        return [
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus",
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone17,3": "iPhone 16",
            "iPhone17,4": "iPhone 16 Plus",
            "iPhone17,1": "iPhone 16 Pro",
            "iPhone17,2": "iPhone 16 Pro Max"
        ][identifier]
    }
}

extension RemoteIPhoneCameraSession: RemoteCameraCaptureRecording {
    func startRemoteCamera(
        take: RecordingTake,
        settings: RecordingSettings,
        hostTimelineStartTime: UInt64
    ) async throws {
        let takeID = UUID()
        let serviceID = RemoteCameraProviderID.serviceID(from: settings.selectedCameraID)
        var startCommandSent = false
        runtime.beginTake(
            takeID: takeID,
            serviceID: serviceID,
            take: take,
            settings: settings
        )
        sendSettings()

        do {
            _ = try await prepare(
                takeID: takeID,
                hostStartTime: DispatchTime.now().uptimeNanoseconds
            )
            markTimelineStart(takeID: takeID, hostTimelineStartTime: hostTimelineStartTime)
            startCommandSent = true
            _ = try await start(
                takeID: takeID,
                hostStartTime: DispatchTime.now().uptimeNanoseconds,
                hostTimelineStartTime: hostTimelineStartTime
            )
        } catch {
            cancelCommand()
            if !startCommandSent {
                removePendingImport(takeID: takeID)
            }
            abandonTake(takeID: takeID)
            throw error
        }
    }

    func pauseRemoteCamera() {}

    func resumeRemoteCamera() {}

    func stopRemoteCamera(take: RecordingTake, settings: RecordingSettings) async throws -> MediaWriterCompletion {
        onMessage?("Waiting for iPhone media...")
        return try await runtime.stopAndImport(take: take, settings: settings)
    }
}

import BlitzRecorderCore
import BlitzRecorderTransport
import CoreGraphics
import CoreMedia
import Foundation
import ImageIO
import Network

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
    var remoteHost: NWEndpoint.Host? { get }
}

extension RemoteIPhoneCameraControlling {
    var remoteHost: NWEndpoint.Host? { nil }
}

extension BonjourServiceBrowser: RemoteIPhoneCameraBrowsing {}
extension RemoteCameraControlClient: RemoteIPhoneCameraControlling {}

@MainActor
final class RemoteIPhoneCameraSession {
    private let browser: RemoteIPhoneCameraBrowsing
    let controlClient: RemoteIPhoneCameraControlling
    lazy var runtime = RemoteCameraSessionRuntime(
        sendCommand: { [weak self] command in
            self?.controlClient.send(command)
        },
        onMessage: { [weak self] message in
            self?.onMessage?(message)
        }
    )

    var sessionState = RemoteIPhoneCameraState()
    private var reconnectTasks: [String: Task<Void, Never>] = [:]
    /// Consecutive reconnects without reaching the iPhone; each one waits twice as long, up to 15 seconds.
    private var reconnectAttempts: [String: Int] = [:]
    #if DEBUG
    /// Every connection the Mac opened and why, for the iPhone end-to-end check.
    var connectionLog: [String] = []
    /// Live-view frames this Mac received from the iPhone since launch.
    var previewFramesReceived = 0
    /// While set, the Mac acts as if the network were gone: no connection, no reconnect.
    var isDebugOffline = false
    #endif
    var settingsSendTasks: [String: Task<Void, Never>] = [:]
    var previewSuppressedUntil: [String: Date] = [:]
    private var isDiscoveryStarted = false
    /// When the iPhone last sent anything. A connection that stays silent is dead even if the socket looks open,
    /// as when the iPhone app quits or Wi‑Fi drops without closing it.
    private var lastEventAt = Date.distantPast
    /// What happened to each iPhone the last time it went away, for the Mac to explain while it is gone.
    var absenceNotes: [String: RemoteCameraAbsence.Note] = [:]
    private var silenceWatchdog: Task<Void, Never>?
    private static let silenceLimit: TimeInterval = 8
    let monitorSampleBufferFactory = RemoteCameraMonitorSampleBufferFactory()
    let readSettings: () -> RecordingSettings
    let saveSettings: (RecordingSettings) -> Void
    let screenAspectRatio: () -> CGFloat
    let canAttemptPendingImports: () -> Bool
    private let reconnectDelay: Duration
    let settingsSendDelay: Duration

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

    func selectedRemoteServiceID() -> String? {
        RemoteCameraProviderID.serviceID(from: readSettings().selectedCameraID)
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
            connect(.init(serviceID: serviceID, forceReconnect: isRetryingSelectedRemoteCamera, reason: "camera chosen"))
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
        connect(.init(serviceID: service.id, forceReconnect: false, reason: "direct address"))
        onCameraConfigurationChanged?()
    }

    func startDiscoveryIfNeeded() {
        guard !isDiscoveryStarted else { return }
        isDiscoveryStarted = true

        controlClient.onStateChanged = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self,
                      let serviceID = self.selectedRemoteServiceID() else {
                    return
                }
                self.sessionState.setConnectionState(state, for: serviceID)
                switch state {
                case .connected, .pairing:
                    self.reconnectTasks[serviceID]?.cancel()
                    self.reconnectTasks[serviceID] = nil
                    if state == .connected {
                        self.reconnectAttempts[serviceID] = nil
                        self.absenceNotes[serviceID] = nil
                    }
                case .disconnected, .degraded:
                    self.noteAbsence(.init(kind: .stoppedResponding, since: Date()), serviceID: serviceID)
                    #if DEBUG
                    self.connectionLog.append("\(Date().formatted(.iso8601.time(includingFractionalSeconds: true))) state \(state)")
                    #endif
                    self.scheduleReconnect(serviceID: serviceID)
                default:
                    break
                }
                self.onCameraConfigurationChanged?()
            }
        }
        controlClient.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.lastEventAt = Date()
                self?.handle(event)
            }
        }
        silenceWatchdog = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self?.reconnectIfSilent()
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
                    self.connect(.init(serviceID: service.id, forceReconnect: wasRediscovered,
                                       reason: wasRediscovered ? "rediscovered" : "services changed"))
                } else if let service = self.sessionState.automaticSelection(settings: settings) {
                    settings.selectedCameraID = RemoteCameraProviderID.make(for: service.id)
                    self.saveSettings(settings)
                    self.connect(.init(serviceID: service.id, forceReconnect: false, reason: "automatic selection"))
                }
                self.onCameraConfigurationChanged?()
            }
        }
        browser.start()
    }

    func shutdown() {
        reconnectTasks.values.forEach { $0.cancel() }
        reconnectTasks.removeAll()
        settingsSendTasks.values.forEach { $0.cancel() }
        settingsSendTasks.removeAll()
        controlClient.disconnect()
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
            connect(.init(serviceID: selectedServiceID, forceReconnect: true, reason: "recording needs connection"))
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
            #if DEBUG
            if reconnectTasks[selectedServiceID] == nil {
                connectionLog.append("\(Date().formatted(.iso8601.time(includingFractionalSeconds: true))) readiness check while \(String(describing: sessionState.connectionStates[selectedServiceID]))")
            }
            #endif
            scheduleReconnect(serviceID: selectedServiceID)
        }

        return PermissionBlocker(
            source: .camera,
            permission: "Remote iPhone",
            status: selectedStatus() ?? "not connected",
            recovery: sessionState.connectionStates[selectedServiceID] == .pairing
                ? "Tap Connect on your iPhone to pair it."
                : "Keep the iPhone camera app open and wait for it to reconnect."
        )
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

    private struct ConnectRequest {
        let serviceID: String
        let forceReconnect: Bool
        let reason: String
    }

    #if DEBUG
    /// Drops the iPhone connection for a while, like a Wi‑Fi loss, then lets it reconnect.
    func debugDropConnection(seconds: Double) {
        isDebugOffline = true
        connectionLog.append("\(Date().formatted(.iso8601.time(includingFractionalSeconds: true))) debug network drop")
        controlClient.disconnect()
        if let serviceID = selectedRemoteServiceID() {
            sessionState.setConnectionState(.disconnected, for: serviceID)
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self else { return }
            self.isDebugOffline = false
            guard let serviceID = self.selectedRemoteServiceID() else { return }
            self.connect(.init(serviceID: serviceID, forceReconnect: true, reason: "debug network back"))
        }
    }
    #endif

    private func connect(_ request: ConnectRequest) {
        let serviceID = request.serviceID
        let forceReconnect = request.forceReconnect
        #if DEBUG
        guard !isDebugOffline else { return }
        if forceReconnect || controlClient.connectedServiceID != serviceID {
            connectionLog.append("\(Date().formatted(.iso8601.time(includingFractionalSeconds: true))) \(request.reason)")
            connectionLog = Array(connectionLog.suffix(30))
        }
        #endif
        guard let service = sessionState.service(id: serviceID) else {
            sessionState.setConnectionState(.discovering, for: serviceID)
            return
        }
        // A rediscovery of the iPhone this Mac is already talking to changes nothing.
        guard forceReconnect || controlClient.connectedServiceID != serviceID || !controlClient.isConnected else {
            return
        }
        sessionState.setConnectionState(.pairing, for: serviceID)
        if forceReconnect || controlClient.connectedServiceID != serviceID {
            sessionState.clearSettingsRestoreMarker(for: serviceID)
        }
        controlClient.connect(to: service, forceReconnect: forceReconnect)
    }

    private func reconnectIfSilent() {
        guard let serviceID = selectedRemoteServiceID(),
              isConnected(serviceID: serviceID),
              Date().timeIntervalSince(lastEventAt) > Self.silenceLimit else { return }
        lastEventAt = Date()
        noteAbsence(.init(kind: .stoppedResponding, since: Date()), serviceID: serviceID)
        sessionState.setConnectionState(.disconnected, for: serviceID)
        onCameraConfigurationChanged?()
        connect(.init(serviceID: serviceID, forceReconnect: true, reason: "iPhone went silent"))
    }

    /// The iPhone said goodbye, so the Mac lets go at once instead of waiting for silence. It comes back on its
    /// own when the app opens again and shows up on the network.
    func dropSleepingIPhone(serviceID: String) {
        absenceNotes[serviceID] = .init(kind: .asleep, since: Date())
        reconnectAttempts[serviceID] = nil
        controlClient.disconnect()
        sessionState.setConnectionState(.disconnected, for: serviceID)
        onCameraConfigurationChanged?()
    }

    /// Keeps the first reason an iPhone went away; a goodbye from the iPhone wins over a later silence.
    func noteAbsence(_ note: RemoteCameraAbsence.Note, serviceID: String) {
        if let existing = absenceNotes[serviceID], existing.kind == .asleep || note.kind == existing.kind { return }
        absenceNotes[serviceID] = note
    }

    func selectedAbsence() -> RemoteCameraAbsence? {
        guard let serviceID = selectedRemoteServiceID() else { return nil }
        switch sessionState.connectionState(for: serviceID) {
        case .connected: return nil
        // Reconnect attempts also show as pairing; only a first-time pairing has no note.
        case .pairing where absenceNotes[serviceID] == nil: return nil
        case .pairing, .discovering, .degraded, .disconnected, .unavailable, nil: break
        }
        return RemoteCameraAbsence(
            note: absenceNotes[serviceID],
            hasConnectedBefore: !readSettings().trustedRemoteCameraServiceIDs.isEmpty
        )
    }

    private func scheduleReconnect(serviceID: String) {
        let settings = readSettings()
        guard settings.selectedCameraID == RemoteCameraProviderID.make(for: serviceID),
              reconnectTasks[serviceID] == nil,
              sessionState.containsService(id: serviceID) else {
            return
        }
        let attempt = reconnectAttempts[serviceID, default: 0]
        reconnectAttempts[serviceID] = attempt + 1
        let delay = min(reconnectDelay * (1 << min(attempt, 3)), max(reconnectDelay, .seconds(15)))
        reconnectTasks[serviceID] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            await MainActor.run { [weak self] in
                guard let self,
                      !Task.isCancelled,
                      self.readSettings().selectedCameraID == RemoteCameraProviderID.make(for: serviceID) else {
                    return
                }
                self.reconnectTasks[serviceID] = nil
                self.connect(.init(serviceID: serviceID, forceReconnect: true, reason: "scheduled reconnect"))
            }
        }
    }

    private func isConnected(serviceID: String) -> Bool {
        sessionState.connectionStates[serviceID] == .connected
            && controlClient.connectedServiceID == serviceID
            && controlClient.isConnected
    }
}

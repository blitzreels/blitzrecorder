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
    var settingsSendTasks: [String: Task<Void, Never>] = [:]
    var previewSuppressedUntil: [String: Date] = [:]
    private var isDiscoveryStarted = false
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
                      let serviceID = self.selectedRemoteServiceID() else {
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
}

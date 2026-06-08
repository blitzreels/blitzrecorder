import BlitzRecorderCore
import BlitzRecorderTransport
import Foundation

struct RemoteIPhoneCameraState {
    var services: [DiscoveredBonjourService] = []
    var connectionStates: [String: RemoteCameraConnectionState] = [:]
    var capabilities: [String: RemoteCameraCapabilities] = [:]
    var telemetry: [String: RemoteCameraTelemetry] = [:]
    private var settingsRestoreSentForServiceIDs: Set<String> = []

    mutating func upsertDirectService(_ service: DiscoveredBonjourService) {
        if let existingIndex = services.firstIndex(where: { $0.id == service.id }) {
            services[existingIndex] = service
        } else {
            services.insert(service, at: 0)
        }
    }

    mutating func replaceDiscoveredServices(_ discoveredServices: [DiscoveredBonjourService]) -> Set<String> {
        let previousServiceIDs = Set(services.map(\.id))
        services = discoveredServices
        return previousServiceIDs
    }

    func service(id: String) -> DiscoveredBonjourService? {
        services.first { $0.id == id }
    }

    func containsService(id: String) -> Bool {
        services.contains { $0.id == id }
    }

    func automaticSelection(settings: RecordingSettings) -> DiscoveredBonjourService? {
        guard settings.enabledSources.contains(.camera),
              settings.selectedCameraID == nil else {
            return nil
        }

        let trustedServices = services.filter { settings.trustedRemoteCameraServiceIDs.contains($0.id) }
        if trustedServices.count == 1 {
            return trustedServices[0]
        }
        return services.count == 1 ? services[0] : nil
    }

    mutating func setConnectionState(_ state: RemoteCameraConnectionState, for serviceID: String) {
        connectionStates[serviceID] = state
    }

    func connectionState(for serviceID: String) -> RemoteCameraConnectionState? {
        connectionStates[serviceID]
    }

    mutating func setCapabilities(_ capabilities: RemoteCameraCapabilities, for serviceID: String) {
        self.capabilities[serviceID] = capabilities
    }

    func capabilities(for serviceID: String) -> RemoteCameraCapabilities? {
        capabilities[serviceID]
    }

    func selectedCapabilities(
        settings: RecordingSettings,
        normalizedSettings: (RemoteCameraSettings, String) -> RemoteCameraSettings
    ) -> RemoteCameraCapabilities? {
        guard let selectedServiceID = RemoteCameraProviderID.serviceID(from: settings.selectedCameraID),
              let capabilities = capabilities[selectedServiceID] else {
            return nil
        }
        let proposedSettings = settings.remoteCameraSettingsByServiceID[selectedServiceID]
            ?? telemetry[selectedServiceID]?.activeSettings
            ?? RemoteCameraSettings()
        let remoteSettings = normalizedSettings(proposedSettings, selectedServiceID)
        return capabilities.capabilities(for: remoteSettings.lens)
    }

    mutating func setTelemetry(_ telemetry: RemoteCameraTelemetry, for serviceID: String) {
        self.telemetry[serviceID] = telemetry
    }

    func telemetry(for serviceID: String) -> RemoteCameraTelemetry? {
        telemetry[serviceID]
    }

    mutating func updateTelemetrySettings(for serviceID: String, activeSettings: RemoteCameraSettings) {
        telemetry[serviceID] = RemoteCameraTelemetry(
            phase: telemetry[serviceID]?.phase ?? .idle,
            elapsedSeconds: telemetry[serviceID]?.elapsedSeconds ?? 0,
            batteryLevel: telemetry[serviceID]?.batteryLevel,
            thermalState: telemetry[serviceID]?.thermalState ?? "unknown",
            storageFreeBytes: telemetry[serviceID]?.storageFreeBytes,
            activeSettings: activeSettings,
            transferProgress: telemetry[serviceID]?.transferProgress,
            previewHealth: telemetry[serviceID]?.previewHealth,
            captureWarning: telemetry[serviceID]?.captureWarning
        )
    }

    mutating func clearSettingsRestoreMarker(for serviceID: String) {
        settingsRestoreSentForServiceIDs.remove(serviceID)
    }

    func hasSentSettingsRestore(for serviceID: String) -> Bool {
        settingsRestoreSentForServiceIDs.contains(serviceID)
    }

    mutating func markSettingsRestoreSent(for serviceID: String) {
        settingsRestoreSentForServiceIDs.insert(serviceID)
    }

    func cameraOptions() -> [SourceOption] {
        services.map { service in
            SourceOption(
                id: RemoteCameraProviderID.make(for: service.id),
                name: capabilities[service.id]?.deviceName ?? service.name
            )
        }
    }

    func selectedName(settings: RecordingSettings) -> String? {
        guard let selectedServiceID = RemoteCameraProviderID.serviceID(from: settings.selectedCameraID) else {
            return nil
        }
        return services.first(where: { $0.id == selectedServiceID })?.name
            ?? capabilities[selectedServiceID]?.deviceName
    }

    func selectedStatus(
        settings: RecordingSettings,
        previewHealthStatus: (RemoteCameraPreviewHealth) -> String
    ) -> String? {
        guard let selectedServiceID = RemoteCameraProviderID.serviceID(from: settings.selectedCameraID) else {
            return nil
        }
        if let telemetry = telemetry[selectedServiceID] {
            if let previewHealth = telemetry.previewHealth,
               !previewHealth.isHealthy {
                return previewHealthStatus(previewHealth)
            }
            if let captureWarning = telemetry.captureWarning,
               !captureWarning.isEmpty {
                return captureWarning
            }
            return "\(telemetry.phase.rawValue) · \(Int(telemetry.elapsedSeconds))s"
        }
        if capabilities[selectedServiceID] != nil {
            return "Ready"
        }
        switch connectionStates[selectedServiceID] {
        case .pairing:
            return "Connecting"
        case .connected:
            return "Connected"
        case .degraded:
            return "Connection is weak"
        case .disconnected:
            return "Disconnected"
        case .discovering:
            return "Discovered"
        case .unavailable:
            return "Unavailable"
        case nil:
            return "Waiting for iPhone video"
        }
    }

    func selectedDeviceDescription(
        settings: RecordingSettings,
        marketingName: (String?) -> String?
    ) -> String {
        guard let selectedServiceID = RemoteCameraProviderID.serviceID(from: settings.selectedCameraID) else {
            return selectedName(settings: settings) ?? "No iPhone selected"
        }
        guard let capabilities = capabilities[selectedServiceID] else {
            return selectedName(settings: settings) ?? "No iPhone selected"
        }
        if let modelName = marketingName(capabilities.deviceModelIdentifier) {
            return "\(capabilities.deviceName) - \(modelName)"
        }
        return capabilities.deviceName
    }

    func selectedTelemetry(
        settings: RecordingSettings,
        normalizedSettings: (RemoteCameraSettings, String) -> RemoteCameraSettings
    ) -> RemoteCameraTelemetry? {
        guard let selectedServiceID = RemoteCameraProviderID.serviceID(from: settings.selectedCameraID) else {
            return nil
        }
        guard var telemetry = telemetry[selectedServiceID] else {
            return nil
        }
        if let savedSettings = settings.remoteCameraSettingsByServiceID[selectedServiceID] {
            telemetry.activeSettings = normalizedSettings(savedSettings, selectedServiceID)
        }
        return telemetry
    }

    func deviceSummaries(
        settings: RecordingSettings,
        marketingName: (String?) -> String?,
        previewHealthStatus: (RemoteCameraPreviewHealth) -> String
    ) -> [RemoteCameraDeviceSummary] {
        services.map { service in
            let capabilities = capabilities[service.id]
            let telemetry = telemetry[service.id]
            let state = connectionStates[service.id]
            let cameraID = RemoteCameraProviderID.make(for: service.id)
            let isSelected = settings.selectedCameraID == cameraID
            let isTrusted = settings.trustedRemoteCameraServiceIDs.contains(service.id)
            let modelName = marketingName(capabilities?.deviceModelIdentifier)
            let status: String
            if let telemetry {
                if let previewHealth = telemetry.previewHealth,
                   !previewHealth.isHealthy {
                    status = previewHealthStatus(previewHealth)
                } else if let captureWarning = telemetry.captureWarning,
                          !captureWarning.isEmpty {
                    status = captureWarning
                } else {
                    status = telemetry.phase.rawValue.capitalized
                }
            } else {
                switch state {
                case .pairing:
                    status = "Pairing"
                case .connected:
                    status = capabilities == nil ? "Loading controls" : "Ready"
                case .degraded:
                    status = "Connection issue"
                case .disconnected:
                    status = "Disconnected"
                case .discovering:
                    status = "Found"
                case .unavailable:
                    status = "Unavailable"
                case nil:
                    status = isTrusted ? "Known iPhone" : "Needs pairing"
                }
            }

            let detail: String
            if let modelName {
                detail = modelName
            } else if capabilities != nil {
                detail = "iPhone camera"
            } else if isTrusted {
                detail = "Trusted BlitzRecorder Camera"
            } else {
                detail = "BlitzRecorder Camera app"
            }

            return RemoteCameraDeviceSummary(
                id: service.id,
                cameraID: cameraID,
                name: capabilities?.deviceName ?? service.name,
                detail: detail,
                status: status,
                isSelected: isSelected,
                isReady: capabilities != nil,
                isTrusted: isTrusted,
                lensCount: capabilities?.supportedLenses.count
            )
        }
    }
}

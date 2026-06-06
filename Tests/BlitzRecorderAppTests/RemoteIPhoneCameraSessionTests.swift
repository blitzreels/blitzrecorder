import BlitzRecorderCore
import BlitzRecorderTransport
import Network
@testable import BlitzRecorderApp
import XCTest

@MainActor
final class RemoteIPhoneCameraSessionTests: XCTestCase {
    func testDirectConnectionValidatesHostAndPortBeforeSavingSelection() {
        var settings = RecordingSettings()
        var messages: [String] = []
        let browser = FakeRemoteIPhoneCameraBrowser()
        let control = FakeRemoteIPhoneCameraControl()
        let session = makeSession(
            settings: { settings },
            saveSettings: { settings = $0 },
            browser: browser,
            control: control
        )
        session.onMessage = { messages.append($0) }

        session.connectDirect(host: "  ", portString: "abc")

        XCTAssertNil(settings.selectedCameraID)
        XCTAssertTrue(control.connections.isEmpty)
        XCTAssertEqual(messages, ["Enter the iPhone IP address and the port shown in the companion app."])
    }

    func testDirectConnectionSavesRemoteSelectionAndConnects() {
        var settings = RecordingSettings()
        let browser = FakeRemoteIPhoneCameraBrowser()
        let control = FakeRemoteIPhoneCameraControl()
        let session = makeSession(
            settings: { settings },
            saveSettings: { settings = $0 },
            browser: browser,
            control: control
        )

        session.connectDirect(host: " 127.0.0.1 ", portString: " 49152 ")

        XCTAssertEqual(control.connections.count, 1)
        XCTAssertEqual(control.connections.first?.service.name, "Direct iPhone 127.0.0.1:49152")
        XCTAssertFalse(control.connections.first?.forceReconnect ?? true)
        XCTAssertEqual(
            RemoteCameraProviderID.serviceID(from: settings.selectedCameraID),
            control.connections.first?.service.id
        )
    }

    func testRediscoveredSelectedServiceForcesReconnect() async {
        let service = makeService(id: "Alice-iPhone._blitzrecorder-camera._tcp.local.", name: "Alice iPhone")
        var settings = RecordingSettings()
        settings.selectedCameraID = RemoteCameraProviderID.make(for: service.id)
        let browser = FakeRemoteIPhoneCameraBrowser()
        let control = FakeRemoteIPhoneCameraControl()
        let session = makeSession(
            settings: { settings },
            saveSettings: { settings = $0 },
            browser: browser,
            control: control
        )

        session.startDiscoveryIfNeeded()
        browser.publish(services: [service])
        await Task.yield()

        XCTAssertTrue(browser.didStart)
        XCTAssertEqual(control.connections.count, 1)
        XCTAssertEqual(control.connections.first?.service.id, service.id)
        XCTAssertTrue(control.connections.first?.forceReconnect ?? false)
    }

    func testRemoteSettingsSendIsDebouncedToLatestSettings() async throws {
        var settings = RecordingSettings()
        let browser = FakeRemoteIPhoneCameraBrowser()
        let control = FakeRemoteIPhoneCameraControl()
        let session = makeSession(
            settings: { settings },
            saveSettings: { settings = $0 },
            browser: browser,
            control: control,
            settingsSendDelay: .milliseconds(10)
        )

        session.connectDirect(host: "127.0.0.1", portString: "49152")
        session.applySettingsIntent(.rotationDegrees(90))
        session.applySettingsIntent(.rotationDegrees(270))
        try await waitForRemoteSettingsCommand(in: control)

        let applySettingsCommands = control.commands.compactMap { command -> RemoteCameraSettings? in
            if case .applySettings(let settings) = command {
                return settings
            }
            return nil
        }
        XCTAssertEqual(applySettingsCommands.map(\.rotationDegrees), [270])
    }

    func testAutomaticRotationTelemetryUpdatesSavedRemoteRotation() async {
        let service = makeService(id: "Alice-iPhone._blitzrecorder-camera._tcp.local.", name: "Alice iPhone")
        var settings = RecordingSettings()
        settings.selectedCameraID = RemoteCameraProviderID.make(for: service.id)
        settings.remoteCameraSettingsByServiceID[service.id] = RemoteCameraSettings(
            usesAutomaticRotation: true,
            rotationDegrees: 180
        )
        let browser = FakeRemoteIPhoneCameraBrowser()
        let control = FakeRemoteIPhoneCameraControl()
        let session = makeSession(
            settings: { settings },
            saveSettings: { settings = $0 },
            browser: browser,
            control: control
        )

        session.startDiscoveryIfNeeded()
        browser.publish(services: [service])
        await Task.yield()
        control.publish(.telemetry(makeTelemetry(rotationDegrees: 90)))
        await Task.yield()

        XCTAssertEqual(settings.remoteCameraSettingsByServiceID[service.id]?.rotationDegrees, 90)
    }

    func testManualRotationIgnoresAutomaticRotationTelemetry() async {
        let service = makeService(id: "Alice-iPhone._blitzrecorder-camera._tcp.local.", name: "Alice iPhone")
        var settings = RecordingSettings()
        settings.selectedCameraID = RemoteCameraProviderID.make(for: service.id)
        settings.remoteCameraSettingsByServiceID[service.id] = RemoteCameraSettings(
            usesAutomaticRotation: false,
            rotationDegrees: 180
        )
        let browser = FakeRemoteIPhoneCameraBrowser()
        let control = FakeRemoteIPhoneCameraControl()
        let session = makeSession(
            settings: { settings },
            saveSettings: { settings = $0 },
            browser: browser,
            control: control
        )

        session.startDiscoveryIfNeeded()
        browser.publish(services: [service])
        await Task.yield()
        control.publish(.telemetry(makeTelemetry(rotationDegrees: 90)))
        await Task.yield()

        XCTAssertEqual(settings.remoteCameraSettingsByServiceID[service.id]?.rotationDegrees, 180)
    }

    private func waitForRemoteSettingsCommand(
        in control: FakeRemoteIPhoneCameraControl,
        timeout: Duration = .seconds(1)
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if control.commands.contains(where: {
                if case .applySettings = $0 { return true }
                return false
            }) {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func makeSession(
        settings: @escaping () -> RecordingSettings,
        saveSettings: @escaping (RecordingSettings) -> Void,
        browser: FakeRemoteIPhoneCameraBrowser,
        control: FakeRemoteIPhoneCameraControl,
        settingsSendDelay: Duration = .milliseconds(1)
    ) -> RemoteIPhoneCameraSession {
        RemoteIPhoneCameraSession(
            readSettings: settings,
            saveSettings: saveSettings,
            screenAspectRatio: { SceneLayout.defaultScreenAspectRatio },
            canAttemptPendingImports: { true },
            browser: browser,
            controlClient: control,
            reconnectDelay: .milliseconds(1),
            settingsSendDelay: settingsSendDelay
        )
    }

    private func makeService(id: String, name: String) -> DiscoveredBonjourService {
        DiscoveredBonjourService(
            id: id,
            name: name,
            endpointDescription: "_blitzrecorder-camera._tcp.local.",
            endpoint: .hostPort(host: "127.0.0.1", port: 9)
        )
    }

    private func makeTelemetry(rotationDegrees: Int) -> RemoteCameraTelemetry {
        RemoteCameraTelemetry(
            phase: .idle,
            elapsedSeconds: 0,
            batteryLevel: nil,
            thermalState: "Normal",
            storageFreeBytes: nil,
            activeSettings: RemoteCameraSettings(
                usesAutomaticRotation: true,
                rotationDegrees: rotationDegrees
            )
        )
    }
}

@MainActor
private final class FakeRemoteIPhoneCameraBrowser: RemoteIPhoneCameraBrowsing {
    var onStateChanged: (@Sendable (BonjourServiceState) -> Void)?
    var onServicesChanged: (@Sendable ([DiscoveredBonjourService]) -> Void)?
    private(set) var didStart = false

    func start() {
        didStart = true
    }

    func publish(services: [DiscoveredBonjourService]) {
        onServicesChanged?(services)
    }
}

@MainActor
private final class FakeRemoteIPhoneCameraControl: RemoteIPhoneCameraControlling {
    struct Connection {
        var service: DiscoveredBonjourService
        var forceReconnect: Bool
    }

    var connectedServiceID: String?
    var isConnected = false
    var onMessage: ((String) -> Void)?
    var onStateChanged: ((RemoteCameraConnectionState) -> Void)?
    var onEvent: ((RemoteCameraEvent) -> Void)?
    private(set) var connections: [Connection] = []
    private(set) var commands: [RemoteCameraCommand] = []
    private(set) var pairingRequests: [(shortCode: String, challenge: RemoteCameraPairingChallenge)] = []

    func connect(to service: DiscoveredBonjourService, forceReconnect: Bool) {
        connectedServiceID = service.id
        connections.append(Connection(service: service, forceReconnect: forceReconnect))
    }

    func send(_ command: RemoteCameraCommand) {
        commands.append(command)
    }

    func publish(_ event: RemoteCameraEvent) {
        onEvent?(event)
    }

    func pair(shortCode: String, challenge: RemoteCameraPairingChallenge) {
        pairingRequests.append((shortCode, challenge))
    }

    func disconnect() {
        connectedServiceID = nil
        isConnected = false
    }
}

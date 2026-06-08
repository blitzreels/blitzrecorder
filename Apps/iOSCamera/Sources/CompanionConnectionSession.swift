import BlitzRecorderCore
import BlitzRecorderTransport
import Foundation
import Network
import OSLog
import Security
import UIKit

enum CompanionFrameConnectionState {
    case ready
    case waiting(String)
    case failed(String)
    case cancelled
    case other
}

@MainActor
protocol CompanionFrameConnection: AnyObject {
    var onStateChanged: ((CompanionFrameConnectionState) -> Void)? { get set }
    var onFrameReceived: ((Data) -> Void)? { get set }
    var onFailed: ((String) -> Void)? { get set }

    func start()
    func send(_ event: RemoteCameraEvent, completion: (@Sendable (Error?) -> Void)?)
    func cancel()
}

@MainActor
protocol CompanionConnectionAdvertising: AnyObject {
    var onStateChanged: ((BonjourServiceState) -> Void)? { get set }
    var onConnectionReceived: ((any CompanionFrameConnection) -> Void)? { get set }
    var onListeningPortChanged: ((UInt16) -> Void)? { get set }

    func start() throws
    func stop()
}

protocol CompanionTrustedMacStore {
    func trustedIdentity() -> RemoteCameraMacIdentity?
    func isTrusted(_ identity: RemoteCameraMacIdentity) -> Bool
    func trust(_ identity: RemoteCameraMacIdentity)
}

extension RemoteCameraTrustedMacStore: CompanionTrustedMacStore {}

struct CompanionConnectionDependencies {
    var deviceID: UUID
    var deviceName: @MainActor () -> String
    var trustedMacStore: any CompanionTrustedMacStore
    var advertiserFactory: @MainActor (_ serviceName: String, _ serviceType: String) -> any CompanionConnectionAdvertising
    var makePairingCode: () -> String
    var makeChallengeNonce: () -> Data
    var retryDelay: Duration
    var sleep: @Sendable (Duration) async throws -> Void

    static func live(defaults: UserDefaults = .standard) -> CompanionConnectionDependencies {
        CompanionConnectionDependencies(
            deviceID: Self.loadDeviceID(defaults: defaults),
            deviceName: { UIDevice.current.name },
            trustedMacStore: RemoteCameraTrustedMacStore(),
            advertiserFactory: { serviceName, serviceType in
                BonjourCompanionAdvertiserAdapter(serviceName: serviceName, serviceType: serviceType)
            },
            makePairingCode: Self.makePairingCode,
            makeChallengeNonce: Self.makeChallengeNonce,
            retryDelay: .seconds(3),
            sleep: { duration in
                try await Task.sleep(for: duration)
            }
        )
    }

    private static func makePairingCode() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }

    private static func makeChallengeNonce() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess {
            return Data(bytes)
        }
        return Data((0..<32).map { _ in UInt8.random(in: UInt8.min...UInt8.max) })
    }

    private static func loadDeviceID(defaults: UserDefaults) -> UUID {
        let key = "remoteCamera.deviceID"
        if let value = defaults.string(forKey: key),
           let uuid = UUID(uuidString: value) {
            return uuid
        }
        let uuid = UUID()
        defaults.set(uuid.uuidString, forKey: key)
        return uuid
    }
}

@MainActor
final class BonjourCompanionAdvertiserAdapter: CompanionConnectionAdvertising {
    var onStateChanged: ((BonjourServiceState) -> Void)?
    var onConnectionReceived: ((any CompanionFrameConnection) -> Void)?
    var onListeningPortChanged: ((UInt16) -> Void)?

    private let advertiser: BonjourServiceAdvertiser
    private let frameConnectionFactory: @MainActor (NWConnection) -> any CompanionFrameConnection

    init(
        serviceName: String,
        serviceType: String,
        frameConnectionFactory: @escaping @MainActor (NWConnection) -> any CompanionFrameConnection = {
            JSONFrameConnectionAdapter(connection: JSONFrameConnection(connection: $0))
        }
    ) {
        advertiser = BonjourServiceAdvertiser(serviceName: serviceName, serviceType: serviceType)
        self.frameConnectionFactory = frameConnectionFactory
        advertiser.onStateChanged = { [weak self] state in
            Task { @MainActor in
                self?.onStateChanged?(state)
            }
        }
        advertiser.onConnectionReceived = { [weak self] connection in
            Task { @MainActor in
                guard let self else { return }
                self.onConnectionReceived?(self.frameConnectionFactory(connection))
            }
        }
        advertiser.onListeningPortChanged = { [weak self] port in
            Task { @MainActor in
                self?.onListeningPortChanged?(port)
            }
        }
    }

    func start() throws {
        try advertiser.start()
    }

    func stop() {
        advertiser.stop()
    }
}

@MainActor
final class JSONFrameConnectionAdapter: CompanionFrameConnection {
    var onStateChanged: ((CompanionFrameConnectionState) -> Void)?
    var onFrameReceived: ((Data) -> Void)?
    var onFailed: ((String) -> Void)?

    private let connection: JSONFrameConnection

    init(connection: JSONFrameConnection) {
        self.connection = connection
        connection.onStateChanged = { [weak self] state in
            Task { @MainActor in
                self?.onStateChanged?(Self.frameState(from: state))
            }
        }
        connection.onFrameReceived = { [weak self] data in
            Task { @MainActor in
                self?.onFrameReceived?(data)
            }
        }
        connection.onFailed = { [weak self] message in
            Task { @MainActor in
                self?.onFailed?(message)
            }
        }
    }

    func start() {
        connection.start()
    }

    func send(_ event: RemoteCameraEvent, completion: (@Sendable (Error?) -> Void)? = nil) {
        connection.send(event, completion: completion)
    }

    func cancel() {
        connection.cancel()
    }

    private static func frameState(from state: NWConnection.State) -> CompanionFrameConnectionState {
        switch state {
        case .ready:
            return .ready
        case .waiting(let error):
            return .waiting(error.localizedDescription)
        case .failed(let error):
            return .failed(error.localizedDescription)
        case .cancelled:
            return .cancelled
        default:
            return .other
        }
    }
}

struct CompanionConnectionSnapshot: Equatable {
    var connectionState: RemoteCameraConnectionState
    var pairedMacName: String?
    var statusMessage: String
    var listeningPortLabel: String
    var pairingCode: String
    var isPairedWithMac: Bool
}

@MainActor
final class CompanionConnectionSession {
    private static let logger = Logger(
        subsystem: "dev.blitzreels.blitzrecorder.camera",
        category: "CompanionConnection"
    )

    private static func diagnosticLog(_ message: String) {
        logger.info("\(message, privacy: .public)")
        #if DEBUG
        if let data = "[CompanionConnection] \(message)\n".data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
        #endif
    }

    private static func diagnosticError(_ message: String) {
        logger.error("\(message, privacy: .public)")
        #if DEBUG
        if let data = "[CompanionConnection] ERROR \(message)\n".data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
        #endif
    }

    var onSnapshotChanged: ((CompanionConnectionSnapshot) -> Void)?
    var onCommand: ((RemoteCameraCommand) -> Void)?
    var onPairingCompleted: ((String) -> Void)?
    var onConnectionReplaced: (() -> Void)?
    var onConnectionCancelled: (() -> Void)?
    var onControlChannelClosed: (() -> Void)?
    var isRecordingOnDisconnect: () -> Bool = { false }

    private var advertiser: (any CompanionConnectionAdvertising)?
    private var controlConnection: (any CompanionFrameConnection)?
    private var discoveryRetryTask: Task<Void, Never>?
    private let dependencies: CompanionConnectionDependencies
    private let trustedMacStore: any CompanionTrustedMacStore
    private let deviceID: UUID
    private var pairingState: RemoteCameraPairingState = .waitingForHello
    private var snapshot: CompanionConnectionSnapshot

    init(dependencies: CompanionConnectionDependencies = .live()) {
        self.dependencies = dependencies
        trustedMacStore = dependencies.trustedMacStore
        deviceID = dependencies.deviceID
        snapshot = CompanionConnectionSnapshot(
            connectionState: .discovering,
            pairedMacName: nil,
            statusMessage: "Waiting for Mac",
            listeningPortLabel: "...",
            pairingCode: dependencies.makePairingCode(),
            isPairedWithMac: false
        )
    }

    convenience init(defaults: UserDefaults) {
        self.init(dependencies: .live(defaults: defaults))
    }

    func start() {
        publish()
        startAdvertising()
    }

    func retry() {
        discoveryRetryTask?.cancel()
        discoveryRetryTask = nil
        let previousConnection = controlConnection
        controlConnection = nil
        previousConnection?.cancel()
        snapshot.isPairedWithMac = false
        snapshot.pairedMacName = nil
        pairingState = .waitingForHello
        snapshot.pairingCode = dependencies.makePairingCode()
        snapshot.listeningPortLabel = "Starting"
        snapshot.connectionState = .discovering
        snapshot.statusMessage = "Restarting discovery"
        publish()
        startAdvertising()
    }

    @discardableResult
    func send(
        _ event: RemoteCameraEvent,
        completion: (@Sendable (Error?) -> Void)? = nil
    ) -> Bool {
        guard let controlConnection else {
            completion?(JSONFrameConnectionError.connectionUnavailable)
            return false
        }
        controlConnection.send(event, completion: completion)
        return true
    }

    private func startAdvertising() {
        let previousAdvertiser = advertiser
        advertiser = nil
        previousAdvertiser?.stop()

        Self.diagnosticLog("Starting Bonjour advertiser for \(RemoteCameraConstants.bonjourServiceType)")
        let newAdvertiser = dependencies.advertiserFactory(
            dependencies.deviceName(),
            RemoteCameraConstants.bonjourServiceType
        )
        advertiser = newAdvertiser
        newAdvertiser.onStateChanged = { [weak self, weak newAdvertiser] state in
            guard let self, let newAdvertiser, self.isActiveAdvertiser(newAdvertiser) else { return }
            self.handleAdvertiserState(state)
        }
        newAdvertiser.onConnectionReceived = { [weak self, weak newAdvertiser] connection in
            guard let self, let newAdvertiser, self.isActiveAdvertiser(newAdvertiser) else { return }
            self.acceptMacConnection(connection)
        }
        newAdvertiser.onListeningPortChanged = { [weak self, weak newAdvertiser] port in
            guard let self, let newAdvertiser, self.isActiveAdvertiser(newAdvertiser) else { return }
            Self.diagnosticLog("Bonjour advertiser listening on port \(port)")
            self.snapshot.listeningPortLabel = "\(port)"
            self.publish()
        }
        do {
            try newAdvertiser.start()
        } catch {
            Self.diagnosticError("Bonjour advertiser failed to start: \(error.localizedDescription)")
            if isActiveAdvertiser(newAdvertiser) {
                advertiser = nil
            }
            snapshot.connectionState = .unavailable
            snapshot.statusMessage = "Couldn’t find Mac: \(error.localizedDescription)"
            publish()
            scheduleDiscoveryRetry(reason: "Discovery could not start.")
        }
    }

    private func handleAdvertiserState(_ state: BonjourServiceState) {
        Self.diagnosticLog("Bonjour advertiser state changed: \(String(describing: state))")
        switch state {
        case .ready:
            discoveryRetryTask?.cancel()
            discoveryRetryTask = nil
            snapshot.connectionState = .discovering
            snapshot.statusMessage = "Waiting for Mac"
            publish()
        case .waiting(let message):
            snapshot.connectionState = .degraded
            snapshot.statusMessage = "Waiting for network: \(message)"
            publish()
            scheduleDiscoveryRetry(reason: "Network waiting.")
        case .failed(let message):
            snapshot.connectionState = .unavailable
            snapshot.statusMessage = "Couldn’t find Mac: \(message)"
            publish()
            scheduleDiscoveryRetry(reason: "Discovery failed.")
        case .cancelled:
            snapshot.connectionState = .disconnected
            publish()
            scheduleDiscoveryRetry(reason: "Discovery stopped.")
        case .idle:
            break
        }
    }

    private func scheduleDiscoveryRetry(reason: String) {
        guard !snapshot.isPairedWithMac,
              discoveryRetryTask == nil else {
            return
        }
        snapshot.statusMessage = "\(reason) Trying again..."
        publish()
        discoveryRetryTask = Task { [weak self] in
            guard let self else { return }
            try? await self.dependencies.sleep(self.dependencies.retryDelay)
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled, !self.snapshot.isPairedWithMac else { return }
                self.discoveryRetryTask = nil
                self.retry()
            }
        }
    }

    private func acceptMacConnection(_ connection: any CompanionFrameConnection) {
        Self.diagnosticLog("Accepted Mac control connection")
        discoveryRetryTask?.cancel()
        discoveryRetryTask = nil
        controlConnection?.cancel()
        controlConnection = connection
        onConnectionReplaced?()
        snapshot.isPairedWithMac = false
        pairingState = .waitingForHello
        snapshot.connectionState = .pairing
        snapshot.statusMessage = "Mac found. Waiting for code."
        publish()

        connection.onStateChanged = { [weak self, weak connection] state in
            guard let self, let connection, self.isActiveConnection(connection) else { return }
            self.handleConnectionState(state, connection: connection)
        }
        connection.onFrameReceived = { [weak self] data in
            do {
                let command = try JSONMessageCodec.decode(RemoteCameraCommand.self, from: data)
                self?.handle(command)
            } catch {
                self?.snapshot.statusMessage = "Mac message could not be read: \(error.localizedDescription)"
                self?.publish()
            }
        }
        connection.onFailed = { [weak self] message in
            guard let self else { return }
            self.onControlChannelClosed?()
            self.markMacDisconnected(status: "Mac not connected: \(message)")
        }
        connection.start()
    }

    private func handleConnectionState(_ state: CompanionFrameConnectionState, connection: any CompanionFrameConnection) {
        switch state {
        case .ready:
            snapshot.connectionState = .pairing
            snapshot.statusMessage = "Mac found. Connecting."
            publish()
        case .waiting(let message):
            snapshot.connectionState = .degraded
            snapshot.statusMessage = "Connecting to Mac: \(message)"
            publish()
        case .failed(let message):
            markMacDisconnected(
                status: "Mac not connected: \(message)",
                connection: connection
            )
        case .cancelled:
            onConnectionCancelled?()
            markMacDisconnected(
                status: isRecordingOnDisconnect()
                ? "Mac not connected. Recording continues on iPhone."
                : "Mac not connected",
                connection: connection
            )
        case .other:
            break
        }
    }

    private func markMacDisconnected(status: String, connection: (any CompanionFrameConnection)? = nil) {
        if let connection {
            guard isActiveConnection(connection) else { return }
            controlConnection = nil
        } else {
            controlConnection = nil
        }
        snapshot.isPairedWithMac = false
        snapshot.pairedMacName = nil
        pairingState = .waitingForHello
        snapshot.connectionState = isRecordingOnDisconnect() ? .degraded : .disconnected
        snapshot.statusMessage = status
        publish()
    }

    private func handle(_ command: RemoteCameraCommand) {
        switch command {
        case .hello(let protocolVersion, let macIdentity):
            handleHello(protocolVersion: protocolVersion, macIdentity: macIdentity)
        case .pair(let shortCode, let macIdentity, let proof):
            handlePair(shortCode: shortCode, macIdentity: macIdentity, proof: proof)
        case .requestCapabilities, .applySettings, .prepare, .start, .stop, .requestTransfer:
            guard isCommandAllowed() else { return }
            onCommand?(command)
        case .transferAck, .cancel:
            onCommand?(command)
        }
    }

    private func handleHello(protocolVersion: Int, macIdentity: RemoteCameraMacIdentity) {
        Self.diagnosticLog("Received Mac hello with protocol \(protocolVersion)")
        guard protocolVersion == RemoteCameraConstants.protocolVersion else {
            send(.failed(takeID: nil, reason: "Unsupported protocol \(protocolVersion)"))
            return
        }
        guard RemoteCameraPairingValidator.isValidIdentity(macIdentity) else {
            send(.failed(takeID: nil, reason: "Mac identity fingerprint did not match its public key."))
            return
        }
        let isTrusted = trustedMacStore.isTrusted(macIdentity)
        let challenge = RemoteCameraPairingChallenge(
            deviceID: deviceID,
            deviceName: dependencies.deviceName(),
            shortCode: "",
            challengeNonce: dependencies.makeChallengeNonce(),
            requiresShortCode: !isTrusted
        )
        pairingState = .challenging(macIdentity: macIdentity, challenge: challenge, isTrusted: isTrusted)
        snapshot.connectionState = .pairing
        snapshot.statusMessage = isTrusted ? "Checking trusted Mac" : "Enter this code on your Mac"
        #if DEBUG
        if challenge.requiresShortCode {
            Self.diagnosticLog("Pairing code \(snapshot.pairingCode)")
        }
        #endif
        publish()
        send(.pairingChallenge(challenge))
    }

    private func handlePair(
        shortCode: String,
        macIdentity: RemoteCameraMacIdentity,
        proof: RemoteCameraPairingProof
    ) {
        guard case .challenging(let expectedIdentity, let challenge, let isTrusted) = pairingState else {
            failPairing(reason: "Pairing proof arrived without a challenge.")
            return
        }
        guard expectedIdentity == macIdentity else {
            failPairing(reason: "Mac identity changed during pairing. Try again.")
            return
        }
        guard RemoteCameraPairingValidator.isValidIdentity(macIdentity),
              RemoteCameraPairingValidator.verifyProof(
                proof,
                identity: macIdentity,
                challenge: challenge,
                protocolVersion: RemoteCameraConstants.protocolVersion
              ) else {
            failPairing(reason: "Mac pairing signature was invalid. Try again.")
            return
        }
        let code = RemoteCameraPairingCode.normalized(shortCode)
        guard !challenge.requiresShortCode || code == snapshot.pairingCode else {
            snapshot.pairingCode = dependencies.makePairingCode()
            failPairing(reason: "Pairing code did not match. Try the new code.")
            return
        }
        if !isTrusted {
            trustedMacStore.trust(macIdentity)
        }
        pairingState = .paired(macIdentity)
        completePairing(status: isTrusted ? "Connected to trusted BlitzRecorder Mac" : "Paired with BlitzRecorder")
    }

    private func failPairing(reason: String) {
        snapshot.statusMessage = reason
        publish()
        send(.failed(takeID: nil, reason: reason))
    }

    private func completePairing(status: String) {
        guard let macIdentity = pairingState.pairedIdentity ?? trustedMacStore.trustedIdentity() else {
            snapshot.statusMessage = "Couldn’t connect to Mac."
            publish()
            send(.failed(takeID: nil, reason: "Couldn’t connect to Mac."))
            return
        }
        snapshot.isPairedWithMac = true
        Self.diagnosticLog("Remote camera pairing completed: \(status)")
        discoveryRetryTask?.cancel()
        discoveryRetryTask = nil
        snapshot.connectionState = .connected
        snapshot.pairedMacName = "BlitzRecorder Mac"
        snapshot.statusMessage = "Getting camera ready"
        publish()
        send(.paired(RemoteCameraPairingTrust(
            deviceID: deviceID,
            deviceName: dependencies.deviceName(),
            publicKeyFingerprint: macIdentity.publicKeyFingerprint
        )))
        onPairingCompleted?(status)
    }

    private func isCommandAllowed() -> Bool {
        guard snapshot.isPairedWithMac else {
            snapshot.statusMessage = "Connect to BlitzRecorder before using camera controls."
            publish()
            send(.failed(takeID: nil, reason: "Remote iPhone Camera is not paired."))
            return false
        }
        return true
    }

    private func publish() {
        onSnapshotChanged?(snapshot)
    }

    private func isActiveAdvertiser(_ candidate: any CompanionConnectionAdvertising) -> Bool {
        guard let advertiser else { return false }
        return ObjectIdentifier(advertiser as AnyObject) == ObjectIdentifier(candidate as AnyObject)
    }

    private func isActiveConnection(_ candidate: any CompanionFrameConnection) -> Bool {
        guard let controlConnection else { return false }
        return ObjectIdentifier(controlConnection as AnyObject) == ObjectIdentifier(candidate as AnyObject)
    }
}

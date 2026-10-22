import BlitzRecorderCore
import BlitzRecorderTransport
import Foundation
import OSLog

/// How far a new Mac is through pairing. Trusted Macs skip straight to connected.
enum CompanionPairingStep: Equatable {
    case waitingForMac
    case approval
    case code
    /// The Mac speaks another protocol version; one of the two apps needs an update.
    case updateNeeded(macIsOlder: Bool)
}

struct CompanionConnectionSnapshot: Equatable {
    var connectionState: RemoteCameraConnectionState
    var pairedMacName: String?
    var statusMessage: String
    var listeningPortLabel: String
    var pairingCode: String
    var pairingStep: CompanionPairingStep
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
    }

    private static func diagnosticError(_ message: String) {
        logger.error("\(message, privacy: .public)")
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
    private var candidateConnections: [any CompanionFrameConnection] = []
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
            pairingStep: .waitingForMac,
            isPairedWithMac: false
        )
    }

    var hasTrustedMac: Bool {
        trustedMacStore.trustedIdentity() != nil
    }

    func start() {
        publish()
        startAdvertising()
    }

    func retry() {
        cancelDiscoveryRetry()
        let previousConnection = controlConnection
        controlConnection = nil
        previousConnection?.cancel()
        candidateConnections.forEach { $0.cancel() }
        candidateConnections.removeAll()
        snapshot.isPairedWithMac = false
        snapshot.pairedMacName = nil
        pairingState = .waitingForHello
        snapshot.pairingStep = .waitingForMac
        snapshot.listeningPortLabel = "Starting"
        snapshot.connectionState = .discovering
        snapshot.statusMessage = "Restarting discovery"
        publish()
        startAdvertising()
    }

    /// Leaves the network while the app sleeps, so the Mac does not reconnect to an iPhone that cannot film.
    /// `retry()` comes back when the app opens again.
    func goDark() {
        cancelDiscoveryRetry()
        let previousAdvertiser = advertiser
        advertiser = nil
        previousAdvertiser?.stop()
        let previousConnection = controlConnection
        controlConnection = nil
        previousConnection?.cancel()
        candidateConnections.forEach { $0.cancel() }
        candidateConnections.removeAll()
        snapshot.isPairedWithMac = false
        pairingState = .waitingForHello
        snapshot.pairingStep = .waitingForMac
        snapshot.connectionState = .disconnected
        publish()
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
            cancelDiscoveryRetry()
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

    private func cancelDiscoveryRetry() {
        discoveryRetryTask?.cancel()
        discoveryRetryTask = nil
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

    /// The Mac may open several connections at once, one per network path (Wi‑Fi and peer-to-peer). Each one
    /// waits as a candidate; the first to say hello becomes the control channel and the others are closed.
    private func acceptMacConnection(_ connection: any CompanionFrameConnection) {
        Self.diagnosticLog("Accepted Mac control connection")
        cancelDiscoveryRetry()
        candidateConnections.append(connection)
        if controlConnection == nil {
            snapshot.connectionState = .pairing
            snapshot.statusMessage = "Mac found"
            publish()
        }

        connection.onStateChanged = { [weak self, weak connection] state in
            guard let self, let connection, self.isActiveConnection(connection) else { return }
            self.handleConnectionState(state, connection: connection)
        }
        connection.onFrameReceived = { [weak self, weak connection] data in
            guard let self, let connection else { return }
            do {
                let command = try JSONMessageCodec.decode(RemoteCameraCommand.self, from: data)
                if !self.isActiveConnection(connection) {
                    guard case .hello = command else { return }
                    self.promote(connection)
                }
                self.handle(command)
            } catch {
                self.snapshot.statusMessage = "Mac message could not be read: \(error.localizedDescription)"
                self.publish()
            }
        }
        connection.onFailed = { [weak self, weak connection] message in
            guard let self, let connection else { return }
            guard self.isActiveConnection(connection) else {
                self.candidateConnections.removeAll { $0 === connection }
                return
            }
            self.onControlChannelClosed?()
            self.markMacDisconnected(status: "Mac not connected: \(message)")
        }
        connection.start()
    }

    private func promote(_ connection: any CompanionFrameConnection) {
        let previous = controlConnection
        controlConnection = connection
        previous?.cancel()
        for candidate in candidateConnections where candidate !== connection {
            candidate.cancel()
        }
        candidateConnections.removeAll()
        if previous != nil { onConnectionReplaced?() }
        snapshot.isPairedWithMac = false
        pairingState = .waitingForHello
        snapshot.pairingStep = .waitingForMac
        snapshot.connectionState = .pairing
        snapshot.statusMessage = "Mac found"
        publish()
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
        if let connection, !isActiveConnection(connection) {
            return
        }
        controlConnection = nil
        snapshot.isPairedWithMac = false
        snapshot.pairedMacName = nil
        pairingState = .waitingForHello
        snapshot.pairingStep = .waitingForMac
        snapshot.connectionState = isRecordingOnDisconnect() ? .degraded : .disconnected
        snapshot.statusMessage = status
        publish()
    }

    private func handle(_ command: RemoteCameraCommand) {
        switch command {
        case .hello(let protocolVersion, let macIdentity, let macName):
            handleHello(.init(protocolVersion: protocolVersion, macIdentity: macIdentity, macName: macName))
        case .pair(let shortCode, let macIdentity, let proof):
            handlePair(shortCode: shortCode, macIdentity: macIdentity, proof: proof)
        case .requestCapabilities, .applySettings, .prepare, .start, .stop, .requestTransfer:
            guard isCommandAllowed() else { return }
            onCommand?(command)
        case .transferAck, .cancel:
            onCommand?(command)
        }
    }

    private struct Hello {
        let protocolVersion: Int
        let macIdentity: RemoteCameraMacIdentity
        let macName: String?
    }

    private func handleHello(_ hello: Hello) {
        let macIdentity = hello.macIdentity
        Self.diagnosticLog("Received Mac hello with protocol \(hello.protocolVersion)")
        guard hello.protocolVersion == RemoteCameraConstants.protocolVersion else {
            send(.failed(takeID: nil, reason: RemoteCameraConstants.unsupportedProtocolReason(hello.protocolVersion)))
            snapshot.pairingStep = .updateNeeded(macIsOlder: hello.protocolVersion < RemoteCameraConstants.protocolVersion)
            publish()
            return
        }
        guard RemoteCameraPairingValidator.isValidIdentity(macIdentity) else {
            send(.failed(takeID: nil, reason: "Mac identity fingerprint did not match its public key."))
            return
        }
        snapshot.connectionState = .pairing
        let macName = hello.macName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        snapshot.pairedMacName = macName.isEmpty ? nil : macName
        guard trustedMacStore.isTrusted(macIdentity) else {
            pairingState = .awaitingApproval(macIdentity: macIdentity)
            snapshot.pairingStep = .approval
            snapshot.statusMessage = "\(snapshot.pairedMacName ?? "A Mac") wants to use this iPhone as its camera"
            publish()
            return
        }
        sendChallenge(.init(macIdentity: macIdentity, isTrusted: true, requiresShortCode: false))
    }

    /// One tap on the iPhone pairs the Mac that is asking. It still has to prove its identity with its key.
    func approvePendingMac() {
        guard case .awaitingApproval(let macIdentity) = pairingState else { return }
        sendChallenge(.init(macIdentity: macIdentity, isTrusted: false, requiresShortCode: false))
    }

    /// The fallback: the Mac types the code shown on this iPhone.
    func pairPendingMacWithCode() {
        guard case .awaitingApproval(let macIdentity) = pairingState else { return }
        sendChallenge(.init(macIdentity: macIdentity, isTrusted: false, requiresShortCode: true))
    }

    func declinePendingMac() {
        guard case .awaitingApproval = pairingState else { return }
        pairingState = .waitingForHello
        snapshot.pairingStep = .waitingForMac
        snapshot.statusMessage = "Pairing declined"
        publish()
        send(.failed(takeID: nil, reason: "Pairing was declined on the iPhone."))
    }

    private struct ChallengeRequest {
        let macIdentity: RemoteCameraMacIdentity
        let isTrusted: Bool
        let requiresShortCode: Bool
    }

    private func sendChallenge(_ request: ChallengeRequest) {
        let challenge = RemoteCameraPairingChallenge(
            deviceID: deviceID,
            deviceName: dependencies.deviceName(),
            shortCode: "",
            challengeNonce: dependencies.makeChallengeNonce(),
            requiresShortCode: request.requiresShortCode
        )
        pairingState = .challenging(macIdentity: request.macIdentity, challenge: challenge, isTrusted: request.isTrusted)
        snapshot.pairingStep = request.requiresShortCode ? .code : .waitingForMac
        snapshot.statusMessage = request.isTrusted ? "Checking trusted Mac"
            : request.requiresShortCode ? "Enter this code on your Mac" : "Connecting"
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
        cancelDiscoveryRetry()
        snapshot.connectionState = .connected
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
        advertiser === candidate
    }

    private func isActiveConnection(_ candidate: any CompanionFrameConnection) -> Bool {
        controlConnection === candidate
    }
}

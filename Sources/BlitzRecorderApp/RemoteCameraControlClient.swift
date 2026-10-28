import BlitzRecorderCore
import BlitzRecorderTransport
import CryptoKit
import Foundation
import Network
import OSLog
import Security
import SystemConfiguration

@MainActor
final class RemoteCameraControlClient {
    private var connection: JSONFrameConnection?
    private(set) var connectedServiceID: String?
    private(set) var capabilities: RemoteCameraCapabilities?
    private(set) var telemetry: RemoteCameraTelemetry?
    private(set) var isConnected = false
    private(set) var connectionAttemptCount = 0
    private let macCredential = RemoteCameraMacIdentityStore.load()

    /// The name the iPhone shows for this Mac, as set in System Settings > General > Sharing.
    private static let computerName = SCDynamicStoreCopyComputerName(nil, nil) as String?

    /// Every connection change and iPhone message, so a dropped iPhone can be explained from the Mac's log:
    /// `log show --predicate 'subsystem == "dev.blitzreels.blitzrecorder" && category == "RemoteCamera"'`.
    private static let logger = Logger(subsystem: "dev.blitzreels.blitzrecorder", category: "RemoteCamera")

    var onChanged: (() -> Void)?
    var onMessage: ((String) -> Void)?
    var onStateChanged: ((RemoteCameraConnectionState) -> Void)?
    var onEvent: ((RemoteCameraEvent) -> Void)?

    func connect(to service: DiscoveredBonjourService, forceReconnect: Bool = false) {
        if !forceReconnect, connectedServiceID == service.id, connection != nil {
            return
        }

        cancel()
        connectedServiceID = service.id
        capabilities = nil
        telemetry = nil
        isConnected = false

        let connection = JSONFrameConnection(endpoint: service.endpoint)
        connection.onStateChanged = { [weak self, weak connection] state in
            Task { @MainActor in
                guard let self, let connection, self.connection === connection else { return }
                self.handleState(state, service: service)
            }
        }
        connection.onFrameReceived = { [weak self, weak connection] data in
            Task { @MainActor in
                guard let self, let connection, self.connection === connection else { return }
                self.handleFrame(data)
            }
        }
        connection.onFailed = { [weak self, weak connection] message in
            Task { @MainActor in
                guard let self, let connection, self.connection === connection else { return }
                self.isConnected = false
                self.connection = nil
                self.onStateChanged?(.disconnected)
                self.report("Remote iPhone command channel failed: \(message)")
                self.onChanged?()
            }
        }
        self.connection = connection
        connectionAttemptCount += 1
        connection.start()
        report("Connecting to \(service.name) Remote iPhone Camera...")
        onStateChanged?(.pairing)
        onChanged?()
    }

    var remoteHost: NWEndpoint.Host? {
        connection?.remoteHost
    }

    func send(_ command: RemoteCameraCommand) {
        connection?.send(command) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                self?.report("Remote iPhone command failed: \(error.localizedDescription)")
            }
        }
    }

    func pair(shortCode: String, challenge: RemoteCameraPairingChallenge) {
        do {
            let proof = try macCredential.proof(for: challenge)
            send(.pair(shortCode: shortCode, macIdentity: macCredential.identity, proof: proof))
        } catch {
            report("Remote iPhone pairing proof failed: \(error.localizedDescription)")
        }
    }

    func cancel() {
        connection?.cancel()
        connection = nil
        connectedServiceID = nil
        capabilities = nil
        telemetry = nil
        isConnected = false
        onChanged?()
    }

    func disconnect() {
        cancel()
    }

    private func report(_ message: String) {
        Self.logger.notice("\(message, privacy: .public)")
        onMessage?(message)
    }

    private func handleState(_ state: NWConnection.State, service: DiscoveredBonjourService) {
        if case .cancelled = state {
            Self.logger.notice("Connection to \(service.name, privacy: .public) closed")
        }
        switch state {
        case .ready:
            isConnected = true
            report("Connected to \(service.name). If it asks, tap Connect on the iPhone.")
            onStateChanged?(.pairing)
            send(.hello(
                protocolVersion: RemoteCameraConstants.protocolVersion,
                macIdentity: macCredential.identity,
                macName: Self.computerName
            ))
        case .waiting(let error):
            isConnected = false
            onStateChanged?(.degraded)
            report("Remote iPhone connection waiting: \(error.localizedDescription)")
        case .failed(let error):
            isConnected = false
            connection = nil
            onStateChanged?(.disconnected)
            report("Remote iPhone connection failed: \(error.localizedDescription)")
        case .cancelled:
            isConnected = false
            connection = nil
            onStateChanged?(.disconnected)
        default:
            break
        }
        onChanged?()
    }

    private func handleFrame(_ data: Data) {
        do {
            let event = try JSONMessageCodec.decode(RemoteCameraEvent.self, from: data)
            handle(event)
        } catch {
            report("Invalid Remote iPhone event: \(error.localizedDescription)")
        }
    }

    private func handle(_ event: RemoteCameraEvent) {
        onEvent?(event)
        switch event {
        case .pairingChallenge:
            report("Enter the pairing code shown on the iPhone.")
        case .paired(let trust):
            onStateChanged?(.connected)
            report("Remote iPhone paired: \(trust.deviceName).")
        case .capabilities(let capabilities):
            self.capabilities = capabilities
            report("Remote iPhone ready: \(capabilities.deviceName).")
        case .telemetry(let telemetry):
            if let warning = telemetry.captureWarning, warning != self.telemetry?.captureWarning {
                Self.logger.warning("iPhone warning: \(warning, privacy: .public)")
            }
            self.telemetry = telemetry
        case .prepared:
            report("Remote iPhone prepared.")
        case .started:
            report("Remote iPhone recording started.")
        case .stopped:
            report("Remote iPhone recording stopped.")
        case .monitorFrame:
            break
        case .monitorVideoFrame:
            break
        case .transferReady(_, let fileName, let byteCount, _):
            let size = ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
            report("Remote iPhone transfer ready: \(fileName) (\(size)).")
        case .transferChunk, .transferChannel:
            break
        case .transferComplete(_, let byteCount, _):
            let size = ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
            report("Remote iPhone transfer complete (\(size)).")
        case .failed(_, let reason):
            report("Remote iPhone failed: \(reason)")
        case .goingToSleep:
            report("Remote iPhone is going to sleep.")
        }
        onChanged?()
    }
}

private struct RemoteCameraMacCredential {
    var identity: RemoteCameraMacIdentity
    private var privateKey: Curve25519.Signing.PrivateKey

    init(privateKey: Curve25519.Signing.PrivateKey) {
        self.privateKey = privateKey
        let publicKeyData = privateKey.publicKey.rawRepresentation
        identity = RemoteCameraMacIdentity(
            publicKeyData: publicKeyData,
            publicKeyFingerprint: Self.sha256HexDigest(for: publicKeyData)
        )
    }

    func proof(for challenge: RemoteCameraPairingChallenge) throws -> RemoteCameraPairingProof {
        let payload = RemoteCameraPairingProofPayload.data(
            protocolVersion: RemoteCameraConstants.protocolVersion,
            deviceID: challenge.deviceID,
            challengeNonce: challenge.challengeNonce,
            publicKeyFingerprint: identity.publicKeyFingerprint
        )
        return RemoteCameraPairingProof(
            challengeNonce: challenge.challengeNonce,
            signatureData: try privateKey.signature(for: payload)
        )
    }

    private static func sha256HexDigest(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private enum RemoteCameraMacIdentityStore {
    private static let keychainService = "dev.blitzreels.blitzrecorder.remote-camera"
    private static let keychainAccount = "mac-signing-private-key"
    private static let defaultsFallbackKey = "remoteCamera.macSigningPrivateKey"

    static func load(defaults: UserDefaults = .standard) -> RemoteCameraMacCredential {
        let keychainData = usesKeychainStore ? loadPrivateKeyDataFromKeychain() : nil
        if let data = keychainData ?? defaults.data(forKey: defaultsFallbackKey),
           let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) {
            return RemoteCameraMacCredential(privateKey: privateKey)
        }

        let privateKey = Curve25519.Signing.PrivateKey()
        let rawRepresentation = privateKey.rawRepresentation
        if !usesKeychainStore || !savePrivateKeyDataToKeychain(rawRepresentation) {
            defaults.set(rawRepresentation, forKey: defaultsFallbackKey)
        }
        return RemoteCameraMacCredential(privateKey: privateKey)
    }

    private static var usesKeychainStore: Bool {
#if DEBUG
        ProcessInfo.processInfo.environment["BLITZRECORDER_DEV_USE_KEYCHAIN"] == "1"
#else
        true
#endif
    }

    private static func loadPrivateKeyDataFromKeychain() -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else {
            return nil
        }
        return item as? Data
    }

    private static func savePrivateKeyDataToKeychain(_ data: Data) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)

        var item = query
        item[kSecValueData] = data
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}

import BlitzRecorderCore
import BlitzRecorderTransport
import CryptoKit
import Foundation
import Network
import Security

@MainActor
final class RemoteCameraControlClient {
    private var connection: JSONFrameConnection?
    private(set) var connectedServiceID: String?
    private(set) var capabilities: RemoteCameraCapabilities?
    private(set) var telemetry: RemoteCameraTelemetry?
    private(set) var isConnected = false
    private(set) var connectionAttemptCount = 0
    private let macCredential = RemoteCameraMacIdentityStore.load()

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
                self.onMessage?("Remote iPhone command channel failed: \(message)")
                self.onChanged?()
            }
        }
        self.connection = connection
        connectionAttemptCount += 1
        connection.start()
        onMessage?("Connecting to \(service.name) Remote iPhone Camera...")
        onStateChanged?(.pairing)
        onChanged?()
    }

    func send(_ command: RemoteCameraCommand) {
        connection?.send(command) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                self?.onMessage?("Remote iPhone command failed: \(error.localizedDescription)")
            }
        }
    }

    func pair(shortCode: String, challenge: RemoteCameraPairingChallenge) {
        do {
            let proof = try macCredential.proof(for: challenge)
            send(.pair(shortCode: shortCode, macIdentity: macCredential.identity, proof: proof))
        } catch {
            onMessage?("Remote iPhone pairing proof failed: \(error.localizedDescription)")
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

    private func handleState(_ state: NWConnection.State, service: DiscoveredBonjourService) {
        switch state {
        case .ready:
            isConnected = true
            onMessage?("Connected to \(service.name) Remote iPhone Camera.")
            onStateChanged?(.pairing)
            send(.hello(protocolVersion: RemoteCameraConstants.protocolVersion, macIdentity: macCredential.identity))
        case .waiting(let error):
            isConnected = false
            onStateChanged?(.degraded)
            onMessage?("Remote iPhone connection waiting: \(error.localizedDescription)")
        case .failed(let error):
            isConnected = false
            connection = nil
            onStateChanged?(.disconnected)
            onMessage?("Remote iPhone connection failed: \(error.localizedDescription)")
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
            onMessage?("Invalid Remote iPhone event: \(error.localizedDescription)")
        }
    }

    private func handle(_ event: RemoteCameraEvent) {
        onEvent?(event)
        switch event {
        case .pairingChallenge:
            onMessage?("Enter the pairing code shown on the iPhone.")
        case .paired(let trust):
            onStateChanged?(.connected)
            onMessage?("Remote iPhone paired: \(trust.deviceName).")
        case .capabilities(let capabilities):
            self.capabilities = capabilities
            onMessage?("Remote iPhone ready: \(capabilities.deviceName).")
        case .telemetry(let telemetry):
            self.telemetry = telemetry
        case .prepared:
            onMessage?("Remote iPhone prepared.")
        case .started:
            onMessage?("Remote iPhone recording started.")
        case .stopped:
            onMessage?("Remote iPhone recording stopped.")
        case .monitorFrame:
            break
        case .monitorVideoFrame:
            break
        case .transferReady(_, let fileName, let byteCount, _):
            let size = ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
            onMessage?("Remote iPhone transfer ready: \(fileName) (\(size)).")
        case .transferChunk:
            break
        case .transferComplete(_, let byteCount, _):
            let size = ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
            onMessage?("Remote iPhone transfer complete (\(size)).")
        case .failed(_, let reason):
            onMessage?("Remote iPhone failed: \(reason)")
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

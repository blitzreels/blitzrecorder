import BlitzRecorderCore
import CryptoKit
import Foundation
import Security

enum RemoteCameraPairingState: Equatable {
    case waitingForHello
    case challenging(
        macIdentity: RemoteCameraMacIdentity,
        challenge: RemoteCameraPairingChallenge,
        isTrusted: Bool
    )
    case paired(RemoteCameraMacIdentity)

    var pairedIdentity: RemoteCameraMacIdentity? {
        if case .paired(let identity) = self {
            return identity
        }
        return nil
    }
}

enum RemoteCameraPairingValidator {
    static func isValidIdentity(_ identity: RemoteCameraMacIdentity) -> Bool {
        identity.publicKeyFingerprint == sha256HexDigest(for: identity.publicKeyData)
    }

    static func verifyProof(
        _ proof: RemoteCameraPairingProof,
        identity: RemoteCameraMacIdentity,
        challenge: RemoteCameraPairingChallenge,
        protocolVersion: Int
    ) -> Bool {
        guard proof.challengeNonce == challenge.challengeNonce,
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: identity.publicKeyData) else {
            return false
        }
        let payload = RemoteCameraPairingProofPayload.data(
            protocolVersion: protocolVersion,
            deviceID: challenge.deviceID,
            challengeNonce: challenge.challengeNonce,
            publicKeyFingerprint: identity.publicKeyFingerprint
        )
        return publicKey.isValidSignature(proof.signatureData, for: payload)
    }

    private static func sha256HexDigest(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

final class RemoteCameraTrustedMacStore {
    private let service = "dev.blitzreels.blitzrecorder.camera-companion"
    private let account = "trusted-mac-identity"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func trustedIdentity() -> RemoteCameraMacIdentity? {
        guard let data = loadData(),
              let identity = try? decoder.decode(RemoteCameraMacIdentity.self, from: data),
              RemoteCameraPairingValidator.isValidIdentity(identity) else {
            return nil
        }
        return identity
    }

    func isTrusted(_ identity: RemoteCameraMacIdentity) -> Bool {
        trustedIdentity() == identity
    }

    func trust(_ identity: RemoteCameraMacIdentity) {
        guard RemoteCameraPairingValidator.isValidIdentity(identity),
              let data = try? encoder.encode(identity) else {
            return
        }
        saveData(data)
    }

    private func loadData() -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else {
            return nil
        }
        return item as? Data
    }

    private func saveData(_ data: Data) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)

        var item = query
        item[kSecValueData] = data
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}

struct RemoteCameraRecordingStateMachine {
    private(set) var phase: RemoteCameraRecordingPhase = .idle
    private(set) var takeID: UUID?
    private(set) var recordingURL: URL?
    private(set) var deviceStartTime: UInt64?
    private(set) var deviceStopTime: UInt64?

    mutating func prepare(_ timeline: RemoteCameraTimeline) {
        phase = .preparing
        takeID = timeline.takeID
        recordingURL = nil
        deviceStartTime = nil
        deviceStopTime = nil
    }

    mutating func start(_ timeline: RemoteCameraTimeline, recordingURL: URL?, deviceStartTime: UInt64) {
        phase = .recording
        takeID = timeline.takeID
        self.recordingURL = recordingURL
        self.deviceStartTime = deviceStartTime
        deviceStopTime = nil
    }

    mutating func stop(_ timeline: RemoteCameraTimeline) {
        phase = .stopping
        takeID = timeline.takeID
    }

    mutating func finish(recordingURL: URL, stopReason: String?) {
        phase = .pendingImport
        self.recordingURL = recordingURL
        _ = stopReason
    }

    mutating func markPendingImport(deviceStopTime: UInt64) {
        phase = .pendingImport
        self.deviceStopTime = deviceStopTime
    }

    mutating func transfer(takeID: UUID, recordingURL: URL) {
        phase = .transferring
        self.takeID = takeID
        self.recordingURL = recordingURL
    }

    mutating func markTransferComplete() {
        phase = .pendingImport
    }

    mutating func fail(_ reason: String) {
        phase = .failed
        _ = reason
    }

    mutating func cancel() {
        phase = .idle
        takeID = nil
        recordingURL = nil
        deviceStartTime = nil
        deviceStopTime = nil
    }
}

enum CameraCompanionRecordingError: LocalizedError {
    case cameraUnavailable
    case notRecording

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "Camera unavailable."
        case .notRecording:
            return "Camera is not recording."
        }
    }
}

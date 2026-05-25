import Foundation

public struct RemoteCameraMacIdentity: Codable, Equatable, Sendable {
    public var publicKeyData: Data
    public var publicKeyFingerprint: String

    public init(publicKeyData: Data, publicKeyFingerprint: String) {
        self.publicKeyData = publicKeyData
        self.publicKeyFingerprint = publicKeyFingerprint
    }
}

public struct RemoteCameraPairingProof: Codable, Equatable, Sendable {
    public var challengeNonce: Data
    public var signatureData: Data

    public init(challengeNonce: Data, signatureData: Data) {
        self.challengeNonce = challengeNonce
        self.signatureData = signatureData
    }
}

public enum RemoteCameraPairingProofPayload {
    public static func data(
        protocolVersion: Int,
        deviceID: UUID,
        challengeNonce: Data,
        publicKeyFingerprint: String
    ) -> Data {
        var data = Data()
        append("BlitzRecorderRemoteCameraPairing:v1", to: &data)
        append(String(protocolVersion), to: &data)
        append(deviceID.uuidString.lowercased(), to: &data)
        append(publicKeyFingerprint, to: &data)
        data.append(challengeNonce)
        return data
    }

    private static func append(_ value: String, to data: inout Data) {
        data.append(contentsOf: value.utf8)
        data.append(0)
    }
}

public struct RemoteCameraPairingChallenge: Codable, Equatable, Sendable {
    public var deviceID: UUID
    public var deviceName: String
    public var shortCode: String
    public var challengeNonce: Data
    public var requiresShortCode: Bool
    public var createdAt: Date

    public init(
        deviceID: UUID,
        deviceName: String,
        shortCode: String,
        challengeNonce: Data = Data(),
        requiresShortCode: Bool = true,
        createdAt: Date = Date()
    ) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.shortCode = shortCode
        self.challengeNonce = challengeNonce
        self.requiresShortCode = requiresShortCode
        self.createdAt = createdAt
    }
}

public struct RemoteCameraPairingTrust: Codable, Equatable, Sendable {
    public var deviceID: UUID
    public var deviceName: String
    public var publicKeyFingerprint: String
    public var trustedAt: Date

    public init(
        deviceID: UUID,
        deviceName: String,
        publicKeyFingerprint: String,
        trustedAt: Date = Date()
    ) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.publicKeyFingerprint = publicKeyFingerprint
        self.trustedAt = trustedAt
    }
}

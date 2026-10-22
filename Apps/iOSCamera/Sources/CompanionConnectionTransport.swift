import BlitzRecorderCore
import BlitzRecorderTransport
import Foundation
import Network
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

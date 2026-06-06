import Foundation
import Network

public enum BonjourServiceState: Equatable, Sendable {
    case idle
    case ready
    case waiting(String)
    case failed(String)
    case cancelled
}

public struct DiscoveredBonjourService: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var endpointDescription: String
    public var endpoint: NWEndpoint

    public init(id: String, name: String, endpointDescription: String, endpoint: NWEndpoint) {
        self.id = id
        self.name = name
        self.endpointDescription = endpointDescription
        self.endpoint = endpoint
    }

    public static func == (lhs: DiscoveredBonjourService, rhs: DiscoveredBonjourService) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.endpointDescription == rhs.endpointDescription
    }

    public static func directTCP(host: String, port: UInt16, name: String? = nil) -> DiscoveredBonjourService {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(normalizedHost),
            port: NWEndpoint.Port(rawValue: port) ?? .any
        )
        return DiscoveredBonjourService(
            id: "direct:\(normalizedHost):\(port)",
            name: name ?? "Direct iPhone \(normalizedHost):\(port)",
            endpointDescription: "\(normalizedHost):\(port)",
            endpoint: endpoint
        )
    }
}

public final class BonjourServiceAdvertiser: @unchecked Sendable {
    private let serviceName: String
    private let serviceType: String
    private let queue: DispatchQueue
    private var listener: NWListener?

    public var onStateChanged: (@Sendable (BonjourServiceState) -> Void)?
    public var onConnectionReceived: (@Sendable (NWConnection) -> Void)?
    public var onListeningPortChanged: (@Sendable (UInt16) -> Void)?

    public init(
        serviceName: String,
        serviceType: String,
        queue: DispatchQueue = DispatchQueue(label: "blitzrecorder.bonjour-advertiser")
    ) {
        self.serviceName = serviceName
        self.serviceType = serviceType
        self.queue = queue
    }

    public func start() throws {
        stop()

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        parameters.includePeerToPeer = true

        let listener = try NWListener(using: parameters)
        listener.service = NWListener.Service(name: serviceName, type: serviceType)
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            if case .ready = state,
               let rawPort = listener?.port?.rawValue {
                self?.onListeningPortChanged?(rawPort)
            }
            self?.onStateChanged?(Self.serviceState(from: state))
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.onConnectionReceived?(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func stop() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
    }

    private static func serviceState(from state: NWListener.State) -> BonjourServiceState {
        switch state {
        case .setup:
            return .idle
        case .waiting(let error):
            return .waiting(error.localizedDescription)
        case .ready:
            return .ready
        case .failed(let error):
            return .failed(error.localizedDescription)
        case .cancelled:
            return .cancelled
        @unknown default:
            return .failed("Unknown listener state")
        }
    }
}

public final class BonjourServiceBrowser: @unchecked Sendable {
    private let serviceType: String
    private let queue: DispatchQueue
    private var browser: NWBrowser?

    public var onStateChanged: (@Sendable (BonjourServiceState) -> Void)?
    public var onServicesChanged: (@Sendable ([DiscoveredBonjourService]) -> Void)?

    public init(
        serviceType: String,
        queue: DispatchQueue = DispatchQueue(label: "blitzrecorder.bonjour-browser")
    ) {
        self.serviceType = serviceType
        self.queue = queue
    }

    public func start() {
        stop()

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: parameters)
        browser.stateUpdateHandler = { [weak self] state in
            self?.onStateChanged?(Self.serviceState(from: state))
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let services = results.compactMap(Self.discoveredService(from:)).sorted { $0.name < $1.name }
            self?.onServicesChanged?(services)
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    public func stop() {
        browser?.stateUpdateHandler = nil
        browser?.browseResultsChangedHandler = nil
        browser?.cancel()
        browser = nil
    }

    private static func discoveredService(from result: NWBrowser.Result) -> DiscoveredBonjourService? {
        guard case let .service(name, type, domain, _) = result.endpoint else {
            return nil
        }
        let id = "\(name).\(type).\(domain)"
        return DiscoveredBonjourService(
            id: id,
            name: name,
            endpointDescription: "\(type).\(domain)",
            endpoint: result.endpoint
        )
    }

    private static func serviceState(from state: NWBrowser.State) -> BonjourServiceState {
        switch state {
        case .setup:
            return .idle
        case .waiting(let error):
            return .waiting(error.localizedDescription)
        case .ready:
            return .ready
        case .failed(let error):
            return .failed(error.localizedDescription)
        case .cancelled:
            return .cancelled
        @unknown default:
            return .failed("Unknown browser state")
        }
    }
}

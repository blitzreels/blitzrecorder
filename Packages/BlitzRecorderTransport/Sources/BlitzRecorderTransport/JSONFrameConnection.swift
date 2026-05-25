import Foundation
import Network

public enum JSONFrameConnectionError: Error, Equatable {
    case frameTooLarge(Int)
    case connectionUnavailable
}

public struct JSONLineFramer {
    public static let delimiter = UInt8(ascii: "\n")

    private var buffer = Data()
    private let maximumFrameLength: Int

    public init(maximumFrameLength: Int = 1_048_576) {
        self.maximumFrameLength = maximumFrameLength
    }

    public mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        if buffer.count > maximumFrameLength {
            throw JSONFrameConnectionError.frameTooLarge(buffer.count)
        }

        var frames: [Data] = []
        while let delimiterIndex = buffer.firstIndex(of: Self.delimiter) {
            let frame = buffer[..<delimiterIndex]
            if frame.count > maximumFrameLength {
                throw JSONFrameConnectionError.frameTooLarge(frame.count)
            }
            frames.append(Data(frame))
            buffer.removeSubrange(...delimiterIndex)
        }
        return frames
    }

    public static func encode<Message: Encodable>(_ message: Message) throws -> Data {
        var data = try JSONMessageCodec.encode(message)
        data.append(delimiter)
        return data
    }
}

public final class JSONFrameConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private var framer = JSONLineFramer()
    private var isStarted = false

    public var onStateChanged: (@Sendable (NWConnection.State) -> Void)?
    public var onFrameReceived: (@Sendable (Data) -> Void)?
    public var onFailed: (@Sendable (String) -> Void)?

    public init(
        connection: NWConnection,
        queue: DispatchQueue = DispatchQueue(label: "blitzrecorder.json-frame-connection")
    ) {
        self.connection = connection
        self.queue = queue
    }

    public convenience init(
        endpoint: NWEndpoint,
        queue: DispatchQueue = DispatchQueue(label: "blitzrecorder.json-frame-connection")
    ) {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        parameters.includePeerToPeer = true
        self.init(connection: NWConnection(to: endpoint, using: parameters), queue: queue)
    }

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        connection.stateUpdateHandler = { [weak self] state in
            self?.onStateChanged?(state)
            if case .ready = state {
                self?.receiveNextFrame()
            }
        }
        connection.start(queue: queue)
    }

    public func send<Message: Encodable>(_ message: Message, completion: (@Sendable (Error?) -> Void)? = nil) {
        do {
            let data = try JSONLineFramer.encode(message)
            connection.send(content: data, completion: .contentProcessed { error in
                completion?(error)
            })
        } catch {
            completion?(error)
        }
    }

    public func cancel() {
        connection.stateUpdateHandler = nil
        connection.cancel()
    }

    private func receiveNextFrame() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                self.onFailed?(error.localizedDescription)
                return
            }

            if let data, !data.isEmpty {
                do {
                    for frame in try self.framer.append(data) {
                        self.onFrameReceived?(frame)
                    }
                } catch {
                    self.onFailed?(error.localizedDescription)
                    self.cancel()
                    return
                }
            }

            if isComplete {
                self.cancel()
            } else {
                self.receiveNextFrame()
            }
        }
    }
}

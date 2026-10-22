import Foundation
import Network
import Security

/// Moves a recording as plain bytes on its own TCP connection, so a large clip neither goes through JSON nor
/// waits behind the live view. The sender gives out a one-time token over the already trusted control channel;
/// the receiver connects, sends the token, and reads the file from the agreed offset until the sender closes.
public enum RawFileTransfer {
    static let greetingPrefix = "BLITZFILE1 "
    static let chunkSize = 1 << 20
    static let maximumGreetingLength = 256

    public enum Failure: LocalizedError, Equatable {
        case listenerUnavailable(String)
        case connectionFailed(String)
        case incomplete(expected: Int64, received: Int64)

        public var errorDescription: String? {
            switch self {
            case .listenerUnavailable(let reason): "The iPhone could not open a transfer channel: \(reason)"
            case .connectionFailed(let reason): "The transfer channel closed: \(reason)"
            case .incomplete(let expected, let received): "The transfer stopped at \(received) of \(expected) bytes."
            }
        }
    }

    static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func parameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }
}

/// The sending side, on the iPhone. One listener serves every offer; each token works once.
public final class RawFileTransferServer: @unchecked Sendable {
    public struct Offer: Sendable {
        public let fileURL: URL
        public let offset: Int64

        public init(fileURL: URL, offset: Int64) {
            self.fileURL = fileURL
            self.offset = offset
        }
    }

    public enum Outcome: Sendable, Equatable {
        case sent(byteCount: Int64)
        case failed(String)
    }

    /// Called on a background queue once an offer has been fully handed to the network, or has failed.
    public var onFinished: (@Sendable (String, Outcome) -> Void)?
    /// Called when a receiver presents the token and sending begins.
    public var onStarted: (@Sendable (String) -> Void)?
    /// Bytes of the file handed to the network so far, counted from the start of the file.
    public var onProgress: (@Sendable (String, Int64) -> Void)?

    private let queue = DispatchQueue(label: "blitzrecorder.raw-file-transfer.server")
    private var listener: NWListener?
    private var port: UInt16?
    private var offers: [String: Offer] = [:]

    public init() {}

    /// Starts listening if needed and returns the port the receiver connects to.
    public func start() async throws -> UInt16 {
        if let port = queue.sync(execute: { self.port }) { return port }
        let listener: NWListener
        do {
            listener = try NWListener(using: RawFileTransfer.parameters(), on: .any)
        } catch {
            throw RawFileTransfer.Failure.listenerUnavailable(error.localizedDescription)
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.serve(connection)
        }
        return try await withCheckedThrowingContinuation { continuation in
            let resumed = Resumed()
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    let port = listener.port?.rawValue ?? 0
                    self?.queue.async { self?.port = port }
                    if resumed.claim() { continuation.resume(returning: port) }
                case .failed(let error):
                    self?.queue.async {
                        self?.listener = nil
                        self?.port = nil
                    }
                    if resumed.claim() {
                        continuation.resume(throwing: RawFileTransfer.Failure.listenerUnavailable(error.localizedDescription))
                    }
                case .cancelled:
                    if resumed.claim() {
                        continuation.resume(throwing: RawFileTransfer.Failure.listenerUnavailable("cancelled"))
                    }
                default:
                    break
                }
            }
            queue.sync { self.listener = listener }
            listener.start(queue: queue)
        }
    }

    /// Registers a file to send and returns the one-time token the receiver must present.
    public func offer(_ offer: Offer) -> String {
        let token = RawFileTransfer.makeToken()
        queue.sync { offers[token] = offer }
        return token
    }

    public func revoke(_ token: String) {
        queue.async { self.offers.removeValue(forKey: token) }
    }

    public func stop() {
        queue.sync {
            listener?.cancel()
            listener = nil
            port = nil
            offers.removeAll()
        }
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        readGreeting(connection, buffer: Data())
    }

    private func readGreeting(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: RawFileTransfer.maximumGreetingLength) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = String(decoding: buffer[..<newline], as: UTF8.self)
                guard line.hasPrefix(RawFileTransfer.greetingPrefix),
                      case let token = String(line.dropFirst(RawFileTransfer.greetingPrefix.count)),
                      let offer = self.offers.removeValue(forKey: token) else {
                    connection.cancel()
                    return
                }
                self.onStarted?(token)
                self.send(.init(connection: connection, token: token, offer: offer))
                return
            }
            guard error == nil, !isComplete, buffer.count < RawFileTransfer.maximumGreetingLength else {
                connection.cancel()
                return
            }
            self.readGreeting(connection, buffer: buffer)
        }
    }

    private struct Sending {
        let connection: NWConnection
        let token: String
        let offer: Offer
    }

    private func send(_ sending: Sending) {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: sending.offer.fileURL)
            try handle.seek(toOffset: UInt64(max(0, sending.offer.offset)))
        } catch {
            sending.connection.cancel()
            onFinished?(sending.token, .failed(error.localizedDescription))
            return
        }
        sendNext(.init(sending: sending, handle: handle, sentByteCount: 0))
    }

    private struct Progress {
        let sending: Sending
        let handle: FileHandle
        let sentByteCount: Int64
    }

    private func sendNext(_ progress: Progress) {
        let connection = progress.sending.connection
        let chunk: Data
        do {
            chunk = try progress.handle.read(upToCount: RawFileTransfer.chunkSize) ?? Data()
        } catch {
            try? progress.handle.close()
            connection.cancel()
            onFinished?(progress.sending.token, .failed(error.localizedDescription))
            return
        }
        guard !chunk.isEmpty else {
            try? progress.handle.close()
            connection.send(content: nil, contentContext: .finalMessage, isComplete: true,
                            completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                if let error {
                    connection.cancel()
                    self.onFinished?(progress.sending.token, .failed(error.localizedDescription))
                    return
                }
                self.onFinished?(progress.sending.token, .sent(byteCount: progress.sentByteCount))
                // The receiver closes once it has read everything; closing first could cut the tail.
                connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, _, _ in connection.cancel() }
                self.queue.asyncAfter(deadline: .now() + 30) { connection.cancel() }
            })
            return
        }
        connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if let error {
                try? progress.handle.close()
                connection.cancel()
                self.onFinished?(progress.sending.token, .failed(error.localizedDescription))
                return
            }
            let sent = progress.sentByteCount + Int64(chunk.count)
            self.onProgress?(progress.sending.token, progress.sending.offer.offset + sent)
            self.sendNext(.init(sending: progress.sending, handle: progress.handle, sentByteCount: sent))
        })
    }
}

/// The receiving side, on the Mac.
public enum RawFileTransferClient {
    public struct Request: Sendable {
        public let host: NWEndpoint.Host
        public let port: UInt16
        public let token: String
        /// The partial file; bytes are written from `offset` onwards.
        public let destinationURL: URL
        public let offset: Int64
        /// The full size of the file being sent.
        public let byteCount: Int64
        /// Total bytes now in the destination file, reported about every megabyte.
        public let onProgress: @Sendable (Int64) -> Void

        public init(host: NWEndpoint.Host, port: UInt16, token: String, destinationURL: URL, offset: Int64,
                    byteCount: Int64, onProgress: @escaping @Sendable (Int64) -> Void) {
            self.host = host
            self.port = port
            self.token = token
            self.destinationURL = destinationURL
            self.offset = offset
            self.byteCount = byteCount
            self.onProgress = onProgress
        }
    }

    /// Receives the file and returns its final size. Throws when the channel closes before every byte arrived.
    public static func receive(_ request: Request) async throws -> Int64 {
        guard let port = NWEndpoint.Port(rawValue: request.port) else {
            throw RawFileTransfer.Failure.connectionFailed("invalid port \(request.port)")
        }
        if !FileManager.default.fileExists(atPath: request.destinationURL.path) {
            FileManager.default.createFile(atPath: request.destinationURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: request.destinationURL)
        try handle.truncate(atOffset: UInt64(max(0, request.offset)))
        let connection = NWConnection(host: request.host, port: port, using: RawFileTransfer.parameters())
        let queue = DispatchQueue(label: "blitzrecorder.raw-file-transfer.client")
        let receiver = Receiver(request: request, connection: connection, handle: handle)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                receiver.continuation = continuation
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        let greeting = Data((RawFileTransfer.greetingPrefix + request.token + "\n").utf8)
                        connection.send(content: greeting, completion: .contentProcessed { error in
                            if let error { receiver.finish(.failure(.connectionFailed(error.localizedDescription))) }
                        })
                        receiver.receiveNext()
                    case .failed(let error):
                        receiver.finish(.failure(.connectionFailed(error.localizedDescription)))
                    case .waiting(let error):
                        receiver.finish(.failure(.connectionFailed(error.localizedDescription)))
                    default:
                        break
                    }
                }
                connection.start(queue: queue)
            }
        } onCancel: {
            connection.cancel()
        }
    }

    private final class Receiver: @unchecked Sendable {
        let request: Request
        let connection: NWConnection
        let handle: FileHandle
        var continuation: CheckedContinuation<Int64, Error>?
        private var total: Int64
        private var lastReported: Int64

        init(request: Request, connection: NWConnection, handle: FileHandle) {
            self.request = request
            self.connection = connection
            self.handle = handle
            total = max(0, request.offset)
            lastReported = total
        }

        func receiveNext() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: RawFileTransfer.chunkSize) {
                [self] data, _, isComplete, error in
                if let data, !data.isEmpty {
                    do {
                        try handle.write(contentsOf: data)
                    } catch {
                        finish(.failure(.connectionFailed(error.localizedDescription)))
                        return
                    }
                    total += Int64(data.count)
                    if total - lastReported >= Int64(RawFileTransfer.chunkSize) {
                        lastReported = total
                        request.onProgress(total)
                    }
                }
                if let error {
                    finish(.failure(.connectionFailed(error.localizedDescription)))
                } else if isComplete {
                    finish(total >= request.byteCount
                           ? .success(total)
                           : .failure(.incomplete(expected: request.byteCount, received: total)))
                } else {
                    receiveNext()
                }
            }
        }

        func finish(_ result: Result<Int64, RawFileTransfer.Failure>) {
            guard let continuation else { return }
            self.continuation = nil
            try? handle.synchronize()
            try? handle.close()
            connection.cancel()
            if case .success(let total) = result { request.onProgress(total) }
            continuation.resume(with: result.mapError { $0 as Error })
        }
    }
}

private final class Resumed: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

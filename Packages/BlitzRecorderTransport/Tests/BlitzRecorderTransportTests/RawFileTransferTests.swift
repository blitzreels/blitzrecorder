import BlitzRecorderTransport
import Foundation
import Network
import XCTest

final class RawFileTransferTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeSource(byteCount: Int) throws -> (URL, Data) {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        for index in bytes.indices { bytes[index] = UInt8(truncatingIfNeeded: index &* 31 &+ index >> 7) }
        let data = Data(bytes)
        let url = directory.appendingPathComponent("source.mov")
        try data.write(to: url)
        return (url, data)
    }

    private struct Run {
        let source: URL
        let destination: URL
        let offset: Int64
        let byteCount: Int64
        let token: String?
    }

    private func transfer(_ run: Run) async throws -> Int64 {
        let server = RawFileTransferServer()
        defer { server.stop() }
        let port = try await server.start()
        let token = server.offer(.init(fileURL: run.source, offset: run.offset))
        return try await RawFileTransferClient.receive(.init(
            host: "127.0.0.1", port: port, token: run.token ?? token, destinationURL: run.destination,
            offset: run.offset, byteCount: run.byteCount, onProgress: { _ in }
        ))
    }

    func testSendsTheWholeFile() async throws {
        let (source, data) = try makeSource(byteCount: 5 * 1_048_576 + 123)
        let destination = directory.appendingPathComponent("camera.mov.partial")
        let total = try await transfer(.init(source: source, destination: destination, offset: 0,
                                             byteCount: Int64(data.count), token: nil))
        XCTAssertEqual(total, Int64(data.count))
        XCTAssertEqual(try Data(contentsOf: destination), data)
    }

    func testResumesFromTheOffsetTheMacAlreadyHas() async throws {
        let (source, data) = try makeSource(byteCount: 3 * 1_048_576)
        let destination = directory.appendingPathComponent("camera.mov.partial")
        let offset = 1_048_576 + 17
        try data.prefix(offset).write(to: destination)
        let total = try await transfer(.init(source: source, destination: destination, offset: Int64(offset),
                                             byteCount: Int64(data.count), token: nil))
        XCTAssertEqual(total, Int64(data.count))
        XCTAssertEqual(try Data(contentsOf: destination), data)
    }

    func testDropsBytesPastTheOffsetBeforeResuming() async throws {
        let (source, data) = try makeSource(byteCount: 2_000_000)
        let destination = directory.appendingPathComponent("camera.mov.partial")
        try (data.prefix(1_000) + Data(repeating: 0xFF, count: 5_000)).write(to: destination)
        _ = try await transfer(.init(source: source, destination: destination, offset: 1_000,
                                     byteCount: Int64(data.count), token: nil))
        XCTAssertEqual(try Data(contentsOf: destination), data)
    }

    func testRefusesAnUnknownToken() async throws {
        let (source, data) = try makeSource(byteCount: 100_000)
        let destination = directory.appendingPathComponent("camera.mov.partial")
        do {
            _ = try await transfer(.init(source: source, destination: destination, offset: 0,
                                         byteCount: Int64(data.count), token: String(repeating: "0", count: 64)))
            XCTFail("An unknown token must not receive the file.")
        } catch {
            XCTAssertEqual((try? Data(contentsOf: destination))?.count ?? 0, 0)
        }
    }

    func testFinishesAtOnceWhenNothingIsLeft() async throws {
        let (source, data) = try makeSource(byteCount: 50_000)
        let destination = directory.appendingPathComponent("camera.mov.partial")
        try data.write(to: destination)
        let total = try await transfer(.init(source: source, destination: destination, offset: Int64(data.count),
                                             byteCount: Int64(data.count), token: nil))
        XCTAssertEqual(total, Int64(data.count))
    }

    func testThroughputOnLoopback() async throws {
        let (source, data) = try makeSource(byteCount: 64 * 1_048_576)
        let destination = directory.appendingPathComponent("camera.mov.partial")
        let started = Date()
        _ = try await transfer(.init(source: source, destination: destination, offset: 0,
                                     byteCount: Int64(data.count), token: nil))
        let rate = Double(data.count) / 1_048_576 / Date().timeIntervalSince(started)
        print("Raw transfer loopback: \(Int(rate)) MB/s")
        XCTAssertGreaterThan(rate, 50)
    }
}

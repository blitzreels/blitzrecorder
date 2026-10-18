import XCTest
@testable import BlitzRecorderApp

final class TranscriptionWorkGateTests: XCTestCase {
    actor Counter {
        var active = 0
        var maximum = 0
        func enter() { active += 1; maximum = max(maximum, active) }
        func leave() { active -= 1 }
    }

    func testModelWorkIsSerializedAcrossConcurrentRequests() async throws {
        let gate = TranscriptionWorkGate()
        let counter = Counter()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    try await gate.acquire()
                    await counter.enter()
                    try await Task.sleep(for: .milliseconds(5))
                    await counter.leave()
                    await gate.release()
                }
            }
            try await group.waitForAll()
        }
        let maximum = await counter.maximum
        XCTAssertEqual(maximum, 1)
    }

    func testCancelledQueuedJobDoesNotBlockFollowingWork() async throws {
        let gate = TranscriptionWorkGate()
        try await gate.acquire()
        let queued = Task { try await gate.acquire() }
        await Task.yield()
        queued.cancel()
        do {
            try await queued.value
            XCTFail("A cancelled queued request must not acquire model access")
        } catch is CancellationError { }
        await gate.release()
        try await gate.acquire()
        await gate.release()
    }
}

import CoreMedia
import Foundation
import ScreenCaptureKit
import XCTest
@testable import BlitzRecorderApp

final class SystemAudioRecorderStartupTests: XCTestCase {
    func testPrewarmedMonitorStreamStartsRecordingWithoutRestartingCapture() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let stream = FakeSystemAudioStream()
        let recorder = SystemAudioRecorder()
        recorder.adoptMonitoringStream(.init(stream: stream, scope: SystemAudioScope(settings: RecordingSettings())))
        let url = directory.appendingPathComponent("system-audio.m4a")

        let startTask = Task {
            try await recorder.start(SystemAudioCaptureStartRequest(
                url: url,
                settings: RecordingSettings(),
                pickedScreenFilter: nil,
                timelineStartTime: nil
            ))
        }
        await stream.waitUntilOutputAttached()
        recorder.receiveAudioSample(try makeSilentAudioSampleBuffer())
        try await startTask.value

        XCTAssertEqual(stream.startCount, 0)
        XCTAssertEqual(stream.addOutputCount, 1)

        let completion = try await recorder.stop()
        XCTAssertTrue(completion.wroteMedia)
        XCTAssertEqual(stream.stopCount, 1)
    }

    func testSwitchingBetweenDisplaysAndWindowsKeepsTheSystemAudioStream() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var displaySettings = RecordingSettings()
        displaySettings.screenSourceBinding = .display(id: "1")
        var windowSettings = displaySettings
        windowSettings.screenSourceBinding = ScreenSourceBinding(
            kind: .window, displayID: nil, bundleIdentifier: "com.example.call",
            applicationName: "Call", processID: nil, windowID: 42, windowTitle: "Call"
        )
        XCTAssertEqual(SystemAudioScope(settings: displaySettings), SystemAudioScope(settings: windowSettings))

        let stream = FakeSystemAudioStream()
        let recorder = SystemAudioRecorder()
        recorder.adoptMonitoringStream(.init(stream: stream, scope: SystemAudioScope(settings: displaySettings)))
        let startTask = Task {
            try await recorder.start(SystemAudioCaptureStartRequest(
                url: directory.appendingPathComponent("system-audio.m4a"),
                settings: displaySettings,
                pickedScreenFilter: nil,
                timelineStartTime: nil
            ))
        }
        await stream.waitUntilOutputAttached()
        recorder.receiveAudioSample(try makeSilentAudioSampleBuffer())
        try await startTask.value

        try await recorder.update(.init(settings: windowSettings, pickedScreenFilter: nil))
        try await recorder.update(.init(settings: displaySettings, pickedScreenFilter: nil))

        XCTAssertEqual(stream.startCount, 0)
        XCTAssertEqual(stream.stopCount, 0)
        _ = try await recorder.stop()
        XCTAssertEqual(stream.stopCount, 1)
    }

    func testAnAppSourceHearsOnlyThatApp() {
        var settings = RecordingSettings()
        settings.screenSourceBinding = Self.app("com.example.call")
        XCTAssertEqual(SystemAudioScope(settings: settings).source, .application("application:com.example.call"))
        settings.screenSourceBinding = Self.app("com.example.other")
        XCTAssertNotEqual(SystemAudioScope(settings: settings).source, .application("application:com.example.call"))
    }

    private static func app(_ bundleIdentifier: String) -> ScreenSourceBinding {
        ScreenSourceBinding(
            kind: .application, displayID: nil, bundleIdentifier: bundleIdentifier,
            applicationName: nil, processID: nil, windowID: nil, windowTitle: nil
        )
    }

    private func makeSilentAudioSampleBuffer() throws -> CMSampleBuffer {
        var description = AudioStreamBasicDescription(
            mSampleRate: 48_000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var formatDescription: CMAudioFormatDescription?
        let formatStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &description,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let formatDescription else {
            throw RecorderError.writerNotReady
        }

        let frames: CMItemCount = 480
        let byteCount = Int(frames) * Int(description.mBytesPerFrame)
        var blockBuffer: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: byteCount,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: byteCount,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard blockStatus == noErr, let blockBuffer else {
            throw RecorderError.writerNotReady
        }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 48_000),
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: frames,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let sampleBuffer else {
            throw RecorderError.writerNotReady
        }
        return sampleBuffer
    }
}

private final class FakeSystemAudioStream: SystemAudioStreaming, @unchecked Sendable {
    private let lock = NSLock()
    private var outputAttached = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var addOutputCount = 0

    func attachAudioOutput(_ request: SystemAudioStreamOutputRequest) throws {
        lock.lock()
        addOutputCount += 1
        outputAttached = true
        let continuations = waiters
        waiters.removeAll()
        lock.unlock()
        continuations.forEach { $0.resume() }
    }

    func startCapture() async throws {
        startCount += 1
    }

    func stopCapture() async throws {
        stopCount += 1
    }

    func updateContentFilter(_ contentFilter: SCContentFilter) async throws {}

    func waitUntilOutputAttached() async {
        if lock.withLock({ outputAttached }) {
            return
        }

        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock {
                if outputAttached {
                    return true
                }
                waiters.append(continuation)
                return false
            }
            if shouldResume {
                continuation.resume()
            }
        }
    }
}

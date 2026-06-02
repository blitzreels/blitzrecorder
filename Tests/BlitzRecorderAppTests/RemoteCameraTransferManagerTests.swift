import BlitzRecorderCore
import Foundation
@testable import BlitzRecorderApp
import XCTest

@MainActor
final class RemoteCameraTransferManagerTests: XCTestCase {
    func testChunkedImportCompletesFileManifestAndPendingRecovery() throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()

        let takeID = UUID()
        let take = makeTake(in: settings.outputDirectory)
        var commands: [RemoteCameraCommand] = []
        var messages: [String] = []
        var finishedTakeIDs: [UUID] = []
        let manager = RemoteCameraTransferManager(
            sendCommand: { commands.append($0) },
            onMessage: { messages.append($0) },
            onTransferFinished: { finishedTakeIDs.append($0) }
        )
        let manifest = RemoteCameraTransferManifest(
            takeID: takeID,
            recordingID: UUID(),
            fileName: "camera.mov",
            byteCount: 5,
            durationSeconds: 1
        )

        manager.registerPendingImport(
            takeID: takeID,
            serviceID: "iphone-15-pro",
            take: take,
            settings: settings
        )
        XCTAssertEqual(manager.beginTransfer(
            takeID: takeID,
            destinationURL: take.cameraURL,
            expectedByteCount: 0,
            settings: settings
        ), 0)
        XCTAssertEqual(RemoteCameraPendingImportStore().all(settings: settings).first?.phase, .transferring)

        manager.applyTransferReady(
            takeID: takeID,
            byteCount: 5,
            manifest: manifest,
            settings: settings,
            hostTimelineStartTime: 11,
            estimatedHostStartTime: 22
        )
        XCTAssertEqual(RemoteCameraPendingImportStore().all(settings: settings).first?.phase, .ready)
        manager.writeChunk(takeID: takeID, offset: 0, data: Data("hello".utf8), isFinal: true)
        manager.completeTransfer(takeID: takeID, byteCount: 5, sha256: nil, settings: settings)

        XCTAssertEqual(try Data(contentsOf: take.cameraURL), Data("hello".utf8))
        XCTAssertEqual(commands, [
            .requestTransfer(takeID: takeID, resumeOffset: 0),
            .transferAck(takeID: takeID, receivedByteCount: 5),
            .transferAck(takeID: takeID, receivedByteCount: 5)
        ])
        XCTAssertEqual(finishedTakeIDs, [takeID])
        XCTAssertTrue(messages.contains { $0.contains("Recovered Remote iPhone camera import") })

        let sidecarURL = take.cameraURL
            .deletingPathExtension()
            .appendingPathExtension("remote-camera-manifest.json")
        let sidecar = try JSONDecoder().decode(
            RemoteCameraTransferManifest.self,
            from: Data(contentsOf: sidecarURL)
        )
        XCTAssertEqual(sidecar.hostTimelineStartTime, 11)
        XCTAssertEqual(sidecar.estimatedHostStartTime, 22)
        XCTAssertTrue(RemoteCameraPendingImportStore().all(settings: settings).isEmpty)
    }

    func testPendingImportDecodesLegacyImportAsWaitingForStop() throws {
        let takeID = UUID()
        let directory = temporaryDirectory()
        let json = """
        [{
          "takeID": "\(takeID.uuidString)",
          "serviceID": "iphone",
          "scratchDirectory": "\(directory.path)",
          "destinationURL": "\(directory.appendingPathComponent("camera.mov").path)",
          "createdAt": 0,
          "expectedByteCount": 42
        }]
        """

        let imports = try JSONDecoder().decode([RemoteCameraPendingImport].self, from: Data(json.utf8))

        XCTAssertEqual(imports.first?.phase, .waitingForStop)
    }

    func testPendingImportDoesNotRequestTransferWhenDestinationCannotOpen() throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        try FileManager.default.createDirectory(at: settings.outputDirectory, withIntermediateDirectories: true)
        let blockedDirectory = settings.outputDirectory.appendingPathComponent("blocked")
        try Data("not a directory".utf8).write(to: blockedDirectory)
        let takeID = UUID()
        var commands: [RemoteCameraCommand] = []
        var finishedTakeIDs: [UUID] = []
        let manager = RemoteCameraTransferManager(
            sendCommand: { commands.append($0) },
            onMessage: { _ in },
            onTransferFinished: { finishedTakeIDs.append($0) }
        )

        RemoteCameraPendingImportStore().upsert(RemoteCameraPendingImport(
            takeID: takeID,
            serviceID: "iphone-15-pro",
            scratchDirectory: blockedDirectory,
            destinationURL: blockedDirectory.appendingPathComponent("camera.mov"),
            createdAt: Date(),
            expectedByteCount: nil
        ), settings: settings)

        manager.requestPendingImports(serviceID: "iphone-15-pro", settings: settings)

        XCTAssertEqual(commands, [])
        XCTAssertEqual(finishedTakeIDs, [takeID])
    }

    private func makeTake(in directory: URL) -> RecordingTake {
        let scratchDirectory = directory.appendingPathComponent("take", isDirectory: true)
        return RecordingTake(
            scratchDirectory: scratchDirectory,
            screenURL: scratchDirectory.appendingPathComponent("screen.mov"),
            cameraURL: scratchDirectory.appendingPathComponent("camera.mov"),
            audioURL: scratchDirectory.appendingPathComponent("audio.m4a"),
            systemAudioURL: scratchDirectory.appendingPathComponent("system-audio.m4a"),
            transcriptURL: scratchDirectory.appendingPathComponent("transcript.txt"),
            finalVideoURL: directory.appendingPathComponent("final.mov"),
            outputVideoFormat: .mov,
            titleSlug: nil
        )
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlitzRecorderTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}

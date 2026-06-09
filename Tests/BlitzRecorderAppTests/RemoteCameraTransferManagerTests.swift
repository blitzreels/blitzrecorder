import BlitzRecorderCore
import AVFoundation
import Foundation
@testable import BlitzRecorderApp
import XCTest

@MainActor
final class RemoteCameraTransferManagerTests: XCTestCase {
    func testChunkedImportCompletesFileManifestAndPendingRecovery() async throws {
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
            onTransferFinished: { finishedTakeIDs.append($0) },
            validateImportedMedia: { _, _ in [] }
        )
        let manifest = RemoteCameraTransferManifest(
            takeID: takeID,
            recordingID: UUID(),
            fileName: "camera.mov",
            byteCount: 5,
            durationSeconds: 1,
            recordingDiagnostics: RemoteCameraRecordingDiagnostics(
                captureRotationDegrees: 180,
                cinematicVideoCaptureEnabled: true,
                simulatedAperture: 2.8,
                recordsOrientationAndMirroringChangesAsMetadataTrack: true,
                firstOrderAmbisonicsAudioSupported: true,
                firstOrderAmbisonicsAudioEnabled: true
            )
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
        await manager.completeTransfer(takeID: takeID, byteCount: 5, sha256: nil, settings: settings)

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
        XCTAssertEqual(sidecar.recordingDiagnostics?.cinematicVideoCaptureEnabled, true)
        XCTAssertEqual(sidecar.recordingDiagnostics?.simulatedAperture, 2.8)
        XCTAssertEqual(sidecar.recordingDiagnostics?.captureRotationDegrees, 180)
        XCTAssertEqual(sidecar.recordingDiagnostics?.recordsOrientationAndMirroringChangesAsMetadataTrack, true)
        XCTAssertEqual(sidecar.recordingDiagnostics?.firstOrderAmbisonicsAudioSupported, true)
        XCTAssertEqual(sidecar.recordingDiagnostics?.firstOrderAmbisonicsAudioEnabled, true)
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

    func testRecordingDiagnosticsSummaryReportsCinematicMismatches() {
        let manifest = RemoteCameraTransferManifest(
            takeID: UUID(),
            recordingID: UUID(),
            fileName: "camera.mov",
            byteCount: 5,
            durationSeconds: 1,
            settings: RemoteCameraSettings(
                cinematicVideoEnabled: true,
                cinematicAperture: 2.8
            ),
            recordingDiagnostics: RemoteCameraRecordingDiagnostics(
                cinematicVideoCaptureEnabled: false,
                simulatedAperture: 4.0,
                recordsOrientationAndMirroringChangesAsMetadataTrack: false,
                captureWarning: "Cinematic needs more light"
            )
        )

        let summary = RemoteCameraTransferManager.recordingDiagnosticsSummary(for: manifest)

        XCTAssertEqual(
            summary,
            "Cinematic was requested but was not active on the iPhone recording. Depth of field recorded at f/4, requested f/2.8. Orientation metadata was not recorded; rotation may need manual correction. Cinematic needs more light"
        )
    }

    func testRecordingDiagnosticsSummaryReportsNonCinematicFormatForCinematicRequest() {
        let manifest = RemoteCameraTransferManifest(
            takeID: UUID(),
            recordingID: UUID(),
            fileName: "camera.mov",
            byteCount: 5,
            durationSeconds: 1,
            settings: RemoteCameraSettings(cinematicVideoEnabled: true),
            format: RemoteCameraFormat(
                id: "1080p-standard",
                width: 1920,
                height: 1080,
                frameRates: [30],
                supportsStabilization: true,
                supportsHDR: false,
                supportsCinematicVideo: false
            ),
            recordingDiagnostics: RemoteCameraRecordingDiagnostics(cinematicVideoCaptureEnabled: true)
        )

        let summary = RemoteCameraTransferManager.recordingDiagnosticsSummary(for: manifest)

        XCTAssertEqual(summary, "Recording format was not Cinematic-capable.")
    }

    func testRecordingDiagnosticsSummaryReportsMissingCinematicFocusMetadata() {
        let manifest = RemoteCameraTransferManifest(
            takeID: UUID(),
            recordingID: UUID(),
            fileName: "camera.mov",
            byteCount: 5,
            durationSeconds: 1,
            settings: RemoteCameraSettings(cinematicVideoEnabled: true),
            recordingDiagnostics: RemoteCameraRecordingDiagnostics(
                cinematicVideoCaptureEnabled: true,
                cinematicFocusMetadataEnabled: false
            )
        )

        let summary = RemoteCameraTransferManager.recordingDiagnosticsSummary(for: manifest)

        XCTAssertEqual(summary, "Cinematic focus metadata was unavailable during recording.")
    }

    func testRecordingDiagnosticsSummaryReportsSavedCinematicAssetVerificationFailure() {
        let manifest = RemoteCameraTransferManifest(
            takeID: UUID(),
            recordingID: UUID(),
            fileName: "camera.mov",
            byteCount: 5,
            durationSeconds: 1,
            settings: RemoteCameraSettings(cinematicVideoEnabled: true),
            recordingDiagnostics: RemoteCameraRecordingDiagnostics(
                cinematicVideoCaptureEnabled: true,
                cinematicAssetVerified: false
            )
        )

        let summary = RemoteCameraTransferManager.recordingDiagnosticsSummary(for: manifest)

        XCTAssertEqual(summary, "The saved iPhone movie did not contain Cinematic depth metadata.")
    }

    func testRecordingDiagnosticsSummaryReportsFormatAndFrameRateMismatch() {
        let manifest = RemoteCameraTransferManifest(
            takeID: UUID(),
            recordingID: UUID(),
            fileName: "camera.mov",
            byteCount: 5,
            durationSeconds: 1,
            settings: RemoteCameraSettings(formatID: "3840x2160", frameRate: 30, colorMode: .standard),
            recordingDiagnostics: RemoteCameraRecordingDiagnostics(
                captureFormatID: "1920x1080",
                captureFrameRate: 24,
                captureColorMode: .appleLog2
            )
        )

        let summary = RemoteCameraTransferManager.recordingDiagnosticsSummary(for: manifest)

        XCTAssertEqual(
            summary,
            "iPhone recorded 1920x1080, requested 3840x2160. iPhone recorded 24 fps, requested 30 fps. iPhone recorded Apple Log 2 color, requested Standard."
        )
    }

    func testRecordingDiagnosticsSummaryReportsStabilizationMismatch() {
        let manifest = RemoteCameraTransferManifest(
            takeID: UUID(),
            recordingID: UUID(),
            fileName: "camera.mov",
            byteCount: 5,
            durationSeconds: 1,
            settings: RemoteCameraSettings(stabilizationMode: .cinematic),
            recordingDiagnostics: RemoteCameraRecordingDiagnostics(
                captureStabilizationMode: .off
            )
        )

        let summary = RemoteCameraTransferManager.recordingDiagnosticsSummary(for: manifest)

        XCTAssertEqual(summary, "iPhone recorded Off stabilization, requested Cinematic.")
    }

    func testRecordingDiagnosticsSummaryAcceptsEnhancedCinematicStabilizationForCinematicRequest() {
        let manifest = RemoteCameraTransferManifest(
            takeID: UUID(),
            recordingID: UUID(),
            fileName: "camera.mov",
            byteCount: 5,
            durationSeconds: 1,
            settings: RemoteCameraSettings(stabilizationMode: .cinematic),
            recordingDiagnostics: RemoteCameraRecordingDiagnostics(
                captureStabilizationMode: .cinematicExtendedEnhanced
            )
        )

        XCTAssertNil(RemoteCameraTransferManager.recordingDiagnosticsSummary(for: manifest))
    }

    func testRecordingDiagnosticsSummaryReportsEnhancedCinematicStabilizationWhenStandardWasRequested() {
        let manifest = RemoteCameraTransferManifest(
            takeID: UUID(),
            recordingID: UUID(),
            fileName: "camera.mov",
            byteCount: 5,
            durationSeconds: 1,
            settings: RemoteCameraSettings(stabilizationMode: .standard),
            recordingDiagnostics: RemoteCameraRecordingDiagnostics(
                captureStabilizationMode: .cinematicExtendedEnhanced
            )
        )

        let summary = RemoteCameraTransferManager.recordingDiagnosticsSummary(for: manifest)

        XCTAssertEqual(summary, "iPhone recorded Cinematic Enhanced stabilization, requested Standard.")
    }

    func testRecordingDiagnosticsSummaryAcceptsResolvedAutoStabilization() {
        let manifest = RemoteCameraTransferManifest(
            takeID: UUID(),
            recordingID: UUID(),
            fileName: "camera.mov",
            byteCount: 5,
            durationSeconds: 1,
            settings: RemoteCameraSettings(stabilizationMode: .auto),
            recordingDiagnostics: RemoteCameraRecordingDiagnostics(
                captureStabilizationMode: .standard
            )
        )

        XCTAssertNil(RemoteCameraTransferManager.recordingDiagnosticsSummary(for: manifest))
    }

    func testRecordingDiagnosticsSummaryReportsRotationMismatch() {
        let manifest = RemoteCameraTransferManifest(
            takeID: UUID(),
            recordingID: UUID(),
            fileName: "camera.mov",
            byteCount: 5,
            durationSeconds: 1,
            settings: RemoteCameraSettings(rotationDegrees: 90),
            recordingDiagnostics: RemoteCameraRecordingDiagnostics(captureRotationDegrees: 180)
        )

        let summary = RemoteCameraTransferManager.recordingDiagnosticsSummary(for: manifest)

        XCTAssertEqual(summary, "iPhone recorded 180 degree rotation, requested 90 degrees.")
    }

    func testRecordingDiagnosticsSummaryReportsMissingRotationDiagnostics() {
        let manifest = RemoteCameraTransferManifest(
            takeID: UUID(),
            recordingID: UUID(),
            fileName: "camera.mov",
            byteCount: 5,
            durationSeconds: 1,
            settings: RemoteCameraSettings(stabilizationMode: .off),
            recordingDiagnostics: RemoteCameraRecordingDiagnostics(observedAtDeviceStartTime: 100)
        )

        let summary = RemoteCameraTransferManager.recordingDiagnosticsSummary(for: manifest)

        XCTAssertEqual(summary, "Rotation was not reported by the iPhone recording.")
    }

    func testRecordingDiagnosticsSummaryReportsMissingStabilizationDiagnostics() {
        let manifest = RemoteCameraTransferManifest(
            takeID: UUID(),
            recordingID: UUID(),
            fileName: "camera.mov",
            byteCount: 5,
            durationSeconds: 1,
            settings: RemoteCameraSettings(stabilizationMode: .standard),
            recordingDiagnostics: RemoteCameraRecordingDiagnostics(
                captureRotationDegrees: 180,
                observedAtDeviceStartTime: 100
            )
        )

        let summary = RemoteCameraTransferManager.recordingDiagnosticsSummary(for: manifest)

        XCTAssertEqual(summary, "Stabilization mode was not reported by the iPhone recording.")
    }

    func testRecordingDiagnosticsSummaryReportsNonHEVCCinematicCodec() {
        let manifest = RemoteCameraTransferManifest(
            takeID: UUID(),
            recordingID: UUID(),
            fileName: "camera.mov",
            byteCount: 5,
            durationSeconds: 1,
            settings: RemoteCameraSettings(cinematicVideoEnabled: true),
            captureCodecLabel: "H.264",
            recordingDiagnostics: RemoteCameraRecordingDiagnostics(cinematicVideoCaptureEnabled: true)
        )

        let summary = RemoteCameraTransferManager.recordingDiagnosticsSummary(for: manifest)

        XCTAssertEqual(
            summary,
            "Cinematic recorded with H.264; HEVC is recommended for iPhone-quality Cinematic recordings."
        )
    }

    func testRecordingDiagnosticsSummarySurfacesCaptureSessionWarning() {
        let manifest = RemoteCameraTransferManifest(
            takeID: UUID(),
            recordingID: UUID(),
            fileName: "camera.mov",
            byteCount: 5,
            durationSeconds: 1,
            recordingDiagnostics: RemoteCameraRecordingDiagnostics(
                captureWarning: "Camera interrupted: iPhone camera is in use by another app"
            )
        )

        let summary = RemoteCameraTransferManager.recordingDiagnosticsSummary(for: manifest)

        XCTAssertEqual(
            summary,
            "Camera interrupted: iPhone camera is in use by another app"
        )
    }

    func testRecordingDiagnosticsSummaryAllowsHEVCCinematicCodec() {
        let manifest = RemoteCameraTransferManifest(
            takeID: UUID(),
            recordingID: UUID(),
            fileName: "camera.mov",
            byteCount: 5,
            durationSeconds: 1,
            settings: RemoteCameraSettings(cinematicVideoEnabled: true),
            captureCodecLabel: "HEVC",
            recordingDiagnostics: RemoteCameraRecordingDiagnostics(cinematicVideoCaptureEnabled: true)
        )

        XCTAssertNil(RemoteCameraTransferManager.recordingDiagnosticsSummary(for: manifest))
    }

    func testRecordingDiagnosticsSummaryReportsMissingSpatialAudioWhenSupported() {
        let manifest = RemoteCameraTransferManifest(
            takeID: UUID(),
            recordingID: UUID(),
            fileName: "camera.mov",
            byteCount: 5,
            durationSeconds: 1,
            settings: RemoteCameraSettings(cinematicVideoEnabled: true),
            recordingDiagnostics: RemoteCameraRecordingDiagnostics(
                cinematicVideoCaptureEnabled: true,
                firstOrderAmbisonicsAudioSupported: true,
                firstOrderAmbisonicsAudioEnabled: false
            )
        )

        let summary = RemoteCameraTransferManager.recordingDiagnosticsSummary(for: manifest)

        XCTAssertEqual(summary, "Spatial audio was supported but not enabled for this Cinematic recording.")
    }

    func testRecordingDiagnosticsSummaryAllowsMissingSpatialAudioWhenUnsupported() {
        let manifest = RemoteCameraTransferManifest(
            takeID: UUID(),
            recordingID: UUID(),
            fileName: "camera.mov",
            byteCount: 5,
            durationSeconds: 1,
            settings: RemoteCameraSettings(cinematicVideoEnabled: true),
            recordingDiagnostics: RemoteCameraRecordingDiagnostics(
                cinematicVideoCaptureEnabled: true,
                firstOrderAmbisonicsAudioSupported: false,
                firstOrderAmbisonicsAudioEnabled: false
            )
        )

        XCTAssertNil(RemoteCameraTransferManager.recordingDiagnosticsSummary(for: manifest))
    }

    func testRecordingDiagnosticsSummaryIsNilForMatchingCinematicRecording() {
        let manifest = RemoteCameraTransferManifest(
            takeID: UUID(),
            recordingID: UUID(),
            fileName: "camera.mov",
            byteCount: 5,
            durationSeconds: 1,
            settings: RemoteCameraSettings(
                cinematicVideoEnabled: true,
                cinematicAperture: 2.8
            ),
            recordingDiagnostics: RemoteCameraRecordingDiagnostics(
                cinematicVideoCaptureEnabled: true,
                simulatedAperture: 2.81,
                recordsOrientationAndMirroringChangesAsMetadataTrack: true
            )
        )

        XCTAssertNil(RemoteCameraTransferManager.recordingDiagnosticsSummary(for: manifest))
    }

    func testTransferReadyIncludesDiagnosticsSummaryInDownloadMessage() throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()

        let takeID = UUID()
        let take = makeTake(in: settings.outputDirectory)
        var messages: [String] = []
        let manager = RemoteCameraTransferManager(
            sendCommand: { _ in },
            onMessage: { messages.append($0) },
            onTransferFinished: { _ in },
            validateImportedMedia: { _, _ in [] }
        )

        XCTAssertEqual(manager.beginTransfer(
            takeID: takeID,
            destinationURL: take.cameraURL,
            expectedByteCount: 0,
            settings: settings
        ), 0)
        manager.applyTransferReady(
            takeID: takeID,
            byteCount: 5,
            manifest: RemoteCameraTransferManifest(
                takeID: takeID,
                recordingID: UUID(),
                fileName: "camera.mov",
                byteCount: 5,
                durationSeconds: 1,
                settings: RemoteCameraSettings(cinematicVideoEnabled: true),
                recordingDiagnostics: RemoteCameraRecordingDiagnostics(cinematicVideoCaptureEnabled: false)
            ),
            settings: settings,
            hostTimelineStartTime: nil,
            estimatedHostStartTime: nil
        )

        XCTAssertTrue(messages.contains {
            $0.contains("Downloading iPhone media")
                && $0.contains("Cinematic was requested but was not active")
        })
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
            onTransferFinished: { finishedTakeIDs.append($0) },
            validateImportedMedia: { _, _ in [] }
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

    func testCompletedImportFailsWhenImportedMediaValidatorFails() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()

        let takeID = UUID()
        let take = makeTake(in: settings.outputDirectory)
        var finishedTakeIDs: [UUID] = []
        var messages: [String] = []
        let manager = RemoteCameraTransferManager(
            sendCommand: { _ in },
            onMessage: { messages.append($0) },
            onTransferFinished: { finishedTakeIDs.append($0) },
            validateImportedMedia: { _, _ in
                throw RecorderError.remoteCameraTransferFailed("Imported iPhone recording has no video track.")
            }
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
        manager.writeChunk(takeID: takeID, offset: 0, data: Data("hello".utf8), isFinal: true)

        let importTask = Task { @MainActor in
            try await manager.waitForStopAndImport(takeID: takeID, take: take, settings: settings)
        }
        await Task.yield()
        await manager.completeTransfer(takeID: takeID, byteCount: 5, sha256: nil, settings: settings)

        do {
            _ = try await importTask.value
            XCTFail("Expected invalid imported media to fail the iPhone import.")
        } catch {
            XCTAssertTrue(String(describing: error).contains("Imported iPhone recording has no video track"))
        }

        XCTAssertEqual(finishedTakeIDs, [takeID])
        XCTAssertTrue(messages.contains("iPhone import failed: the iPhone recording has no usable video. Keep the iPhone app open until recording stops, then retry."))
        XCTAssertFalse(FileManager.default.fileExists(atPath: take.cameraURL.path))
        XCTAssertEqual(RemoteCameraPendingImportStore().all(settings: settings).first?.phase, .failedRecoverable)
    }

    func testCompletedImportSurfacesImportedMediaValidationWarnings() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()

        let takeID = UUID()
        let take = makeTake(in: settings.outputDirectory)
        var messages: [String] = []
        let manager = RemoteCameraTransferManager(
            sendCommand: { _ in },
            onMessage: { messages.append($0) },
            onTransferFinished: { _ in },
            validateImportedMedia: { _, _ in ["orientation metadata track was requested but is missing"] }
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
        manager.writeChunk(takeID: takeID, offset: 0, data: Data("hello".utf8), isFinal: true)

        await manager.completeTransfer(takeID: takeID, byteCount: 5, sha256: nil, settings: settings)

        XCTAssertTrue(messages.contains("iPhone media warning: orientation metadata track was requested but is missing"))
        XCTAssertEqual(try Data(contentsOf: take.cameraURL), Data("hello".utf8))
    }

    func testDefaultImportedMediaValidatorRejectsMissingOrientationMetadataForAutomaticRotation() async throws {
        let directory = temporaryDirectory()
        let movieURL = directory.appendingPathComponent("camera.mov")
        try await writeTinyMovie(to: movieURL)
        let manifest = RemoteCameraTransferManifest(
            takeID: UUID(),
            recordingID: UUID(),
            fileName: "camera.mov",
            byteCount: Int64((try FileManager.default.attributesOfItem(atPath: movieURL.path)[.size] as? NSNumber)?.intValue ?? 0),
            durationSeconds: 0.1,
            settings: RemoteCameraSettings(usesAutomaticRotation: true),
            recordingDiagnostics: RemoteCameraRecordingDiagnostics(
                recordsOrientationAndMirroringChangesAsMetadataTrack: false
            )
        )

        do {
            _ = try await RemoteCameraTransferManager.validateImportedMedia(url: movieURL, manifest: manifest)
            XCTFail("Expected automatic iPhone rotation without orientation metadata to fail import.")
        } catch {
            XCTAssertTrue(String(describing: error).contains("did not include orientation metadata"))
        }
    }

    func testDefaultImportedMediaValidatorRejectsRotationMismatch() async throws {
        let directory = temporaryDirectory()
        let movieURL = directory.appendingPathComponent("camera.mov")
        try await writeTinyMovie(to: movieURL)
        let manifest = RemoteCameraTransferManifest(
            takeID: UUID(),
            recordingID: UUID(),
            fileName: "camera.mov",
            byteCount: Int64((try FileManager.default.attributesOfItem(atPath: movieURL.path)[.size] as? NSNumber)?.intValue ?? 0),
            durationSeconds: 0.1,
            settings: RemoteCameraSettings(
                usesAutomaticRotation: false,
                rotationDegrees: 90
            ),
            recordingDiagnostics: RemoteCameraRecordingDiagnostics(captureRotationDegrees: 0)
        )

        do {
            _ = try await RemoteCameraTransferManager.validateImportedMedia(url: movieURL, manifest: manifest)
            XCTFail("Expected mismatched iPhone recording rotation to fail import.")
        } catch {
            XCTAssertTrue(String(describing: error).contains("rotation mismatch"))
        }
    }

    func testDefaultImportedMediaValidatorWarnsWhenCinematicImportIsNotHEVC() async throws {
        let directory = temporaryDirectory()
        let movieURL = directory.appendingPathComponent("camera.mov")
        try await writeTinyMovie(to: movieURL)
        let manifest = RemoteCameraTransferManifest(
            takeID: UUID(),
            recordingID: UUID(),
            fileName: "camera.mov",
            byteCount: Int64((try FileManager.default.attributesOfItem(atPath: movieURL.path)[.size] as? NSNumber)?.intValue ?? 0),
            durationSeconds: 0.1,
            settings: RemoteCameraSettings(cinematicVideoEnabled: true),
            recordingDiagnostics: RemoteCameraRecordingDiagnostics(cinematicVideoCaptureEnabled: false)
        )

        let warnings = try await RemoteCameraTransferManager.validateImportedMedia(url: movieURL, manifest: manifest)

        XCTAssertTrue(warnings.contains("Cinematic was requested but the imported manifest does not prove it was active"))
        XCTAssertTrue(warnings.contains("Cinematic recording used H.264; HEVC is required for iPhone-quality Cinematic recordings"))
    }

    func testDefaultImportedMediaValidatorRejectsActiveCinematicImportWhenNotHEVC() async throws {
        let directory = temporaryDirectory()
        let movieURL = directory.appendingPathComponent("camera.mov")
        try await writeTinyMovie(to: movieURL)
        let manifest = RemoteCameraTransferManifest(
            takeID: UUID(),
            recordingID: UUID(),
            fileName: "camera.mov",
            byteCount: Int64((try FileManager.default.attributesOfItem(atPath: movieURL.path)[.size] as? NSNumber)?.intValue ?? 0),
            durationSeconds: 0.1,
            settings: RemoteCameraSettings(cinematicVideoEnabled: true),
            recordingDiagnostics: RemoteCameraRecordingDiagnostics(cinematicVideoCaptureEnabled: true)
        )

        do {
            _ = try await RemoteCameraTransferManager.validateImportedMedia(url: movieURL, manifest: manifest)
            XCTFail("Expected active Cinematic media with a non-HEVC video track to fail import.")
        } catch {
            XCTAssertTrue(String(describing: error).contains("HEVC is required"))
        }
    }

    func testDefaultImportedMediaValidatorRejectsManifestReportedCinematicAssetFailure() async throws {
        let directory = temporaryDirectory()
        let movieURL = directory.appendingPathComponent("camera.mov")
        try await writeTinyMovie(to: movieURL, codec: .hevc)
        let manifest = RemoteCameraTransferManifest(
            takeID: UUID(),
            recordingID: UUID(),
            fileName: "camera.mov",
            byteCount: Int64((try FileManager.default.attributesOfItem(atPath: movieURL.path)[.size] as? NSNumber)?.intValue ?? 0),
            durationSeconds: 0.1,
            settings: RemoteCameraSettings(cinematicVideoEnabled: true),
            recordingDiagnostics: RemoteCameraRecordingDiagnostics(
                cinematicVideoCaptureEnabled: true,
                cinematicAssetVerified: false
            )
        )

        do {
            _ = try await RemoteCameraTransferManager.validateImportedMedia(url: movieURL, manifest: manifest)
            XCTFail("Expected a manifest-reported Cinematic asset failure to reject import.")
        } catch {
            XCTAssertTrue(String(describing: error).contains("without Cinematic depth metadata"))
        }
    }

    func testDefaultImportedMediaValidatorRejectsNonCinematicMovieWhenCinematicWasActive() async throws {
        let directory = temporaryDirectory()
        let movieURL = directory.appendingPathComponent("camera.mov")
        try await writeTinyMovie(to: movieURL, codec: .hevc)
        let manifest = RemoteCameraTransferManifest(
            takeID: UUID(),
            recordingID: UUID(),
            fileName: "camera.mov",
            byteCount: Int64((try FileManager.default.attributesOfItem(atPath: movieURL.path)[.size] as? NSNumber)?.intValue ?? 0),
            durationSeconds: 0.1,
            settings: RemoteCameraSettings(cinematicVideoEnabled: true),
            recordingDiagnostics: RemoteCameraRecordingDiagnostics(cinematicVideoCaptureEnabled: true)
        )

        do {
            _ = try await RemoteCameraTransferManager.validateImportedMedia(url: movieURL, manifest: manifest)
            XCTFail("Expected a non-Cinematic movie to be rejected when the iPhone reported active Cinematic capture.")
        } catch {
            XCTAssertTrue(String(describing: error).contains("not a Cinematic asset"))
        }
    }

    func testDefaultImportedMediaValidatorRejectsManifestWithNonCinematicFormatWhenCinematicWasRequested() async throws {
        let directory = temporaryDirectory()
        let movieURL = directory.appendingPathComponent("camera.mov")
        try await writeTinyMovie(to: movieURL)
        let manifest = RemoteCameraTransferManifest(
            takeID: UUID(),
            recordingID: UUID(),
            fileName: "camera.mov",
            byteCount: Int64((try FileManager.default.attributesOfItem(atPath: movieURL.path)[.size] as? NSNumber)?.intValue ?? 0),
            durationSeconds: 0.1,
            settings: RemoteCameraSettings(cinematicVideoEnabled: true),
            format: RemoteCameraFormat(
                id: "1080p-standard",
                width: 1920,
                height: 1080,
                frameRates: [30],
                supportsStabilization: true,
                supportsHDR: false,
                supportsCinematicVideo: false
            ),
            recordingDiagnostics: RemoteCameraRecordingDiagnostics(cinematicVideoCaptureEnabled: true)
        )

        do {
            _ = try await RemoteCameraTransferManager.validateImportedMedia(url: movieURL, manifest: manifest)
            XCTFail("Expected a Cinematic request with a non-Cinematic format to be rejected.")
        } catch {
            XCTAssertTrue(String(describing: error).contains("recording format was not Cinematic-capable"))
        }
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

    private func writeTinyMovie(
        to url: URL,
        codec: AVVideoCodecType = .h264
    ) async throws {
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: codec,
                AVVideoWidthKey: 64,
                AVVideoHeightKey: 64
            ]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 64,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )
        guard writer.canAdd(input) else {
            throw RecorderError.writerNotReady
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? RecorderError.writerNotReady
        }
        writer.startSession(atSourceTime: .zero)
        guard let pool = adaptor.pixelBufferPool else {
            throw RecorderError.writerNotReady
        }

        for frame in 0..<3 {
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            guard let pixelBuffer else {
                throw RecorderError.writerNotReady
            }
            fill(pixelBuffer, red: UInt8(60 + frame * 40))
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(1))
            }
            guard adaptor.append(
                pixelBuffer,
                withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30)
            ) else {
                throw writer.error ?? RecorderError.writerNotReady
            }
        }

        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }
        guard writer.status == .completed else {
            throw writer.error ?? RecorderError.writerNotReady
        }
    }

    private func fill(_ pixelBuffer: CVPixelBuffer, red: UInt8) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        for y in 0..<height {
            let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let index = x * 4
                row[index] = 24
                row[index + 1] = 42
                row[index + 2] = red
                row[index + 3] = 255
            }
        }
    }
}

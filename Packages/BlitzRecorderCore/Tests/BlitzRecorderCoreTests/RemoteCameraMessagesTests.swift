import XCTest
@testable import BlitzRecorderCore

final class RemoteCameraMessagesTests: XCTestCase {
    private let macIdentity = RemoteCameraMacIdentity(
        publicKeyData: Data([1, 2, 3, 4]),
        publicKeyFingerprint: "fingerprint"
    )
    private let pairingProof = RemoteCameraPairingProof(
        challengeNonce: Data([9, 8, 7, 6]),
        signatureData: Data([5, 4, 3, 2])
    )

    func testCommandRoundTrip() throws {
        let command = RemoteCameraCommand.applySettings(RemoteCameraSettings(
            lens: .telephoto,
            formatID: "4k-30",
            frameRate: 60,
            captureProfileID: .proRes422,
            colorMode: .appleLog2,
            zoomFactor: 2.5,
            focusMode: .manual,
            focusPosition: 0.65,
            exposureMode: .manual,
            exposureBias: -0.3,
            iso: 320,
            shutterDurationSeconds: 1.0 / 120.0,
            whiteBalanceMode: .manual,
            whiteBalanceTemperature: 4_800,
            whiteBalanceTint: 12,
            stabilizationMode: .cinematic,
            rotationDegrees: 180,
            torchEnabled: true,
            cinematicVideoEnabled: true,
            cinematicAperture: 2.8
        ))

        let data = try JSONEncoder().encode(command)
        let decoded = try JSONDecoder().decode(RemoteCameraCommand.self, from: data)

        XCTAssertEqual(decoded, command)
    }

    func testPairCommandRoundTrip() throws {
        let command = RemoteCameraCommand.pair(
            shortCode: "123456",
            macIdentity: macIdentity,
            proof: pairingProof
        )

        let data = try JSONEncoder().encode(command)
        let decoded = try JSONDecoder().decode(RemoteCameraCommand.self, from: data)

        XCTAssertEqual(decoded, command)
    }

    func testHelloCommandRoundTripIncludesMacIdentity() throws {
        let command = RemoteCameraCommand.hello(protocolVersion: 1, macIdentity: macIdentity)

        let data = try JSONEncoder().encode(command)
        let decoded = try JSONDecoder().decode(RemoteCameraCommand.self, from: data)

        XCTAssertEqual(decoded, command)
    }

    func testRequestTransferCommandRoundTrip() throws {
        let command = RemoteCameraCommand.requestTransfer(takeID: UUID(), resumeOffset: 1_048_576)

        let data = try JSONEncoder().encode(command)
        let decoded = try JSONDecoder().decode(RemoteCameraCommand.self, from: data)

        XCTAssertEqual(decoded, command)
    }

    func testTransferAckCommandRoundTrip() throws {
        let command = RemoteCameraCommand.transferAck(takeID: UUID(), receivedByteCount: 524_288)

        let data = try JSONEncoder().encode(command)
        let decoded = try JSONDecoder().decode(RemoteCameraCommand.self, from: data)

        XCTAssertEqual(decoded, command)
    }

    func testPairingChallengeEventRoundTrip() throws {
        let challenge = RemoteCameraPairingChallenge(
            deviceID: UUID(),
            deviceName: "Alice iPhone",
            shortCode: "123456",
            challengeNonce: Data([1, 3, 5, 7]),
            requiresShortCode: true
        )
        let event = RemoteCameraEvent.pairingChallenge(challenge)

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(RemoteCameraEvent.self, from: data)

        XCTAssertEqual(decoded, event)
    }

    func testTransferChunkEventRoundTrip() throws {
        let takeID = UUID()
        let event = RemoteCameraEvent.transferChunk(
            takeID: takeID,
            offset: 262_144,
            data: Data([0, 1, 2, 253, 254, 255]),
            isFinal: true
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(RemoteCameraEvent.self, from: data)

        XCTAssertEqual(decoded, event)
    }

    func testTransferReadyEventRoundTripIncludesManifest() throws {
        let takeID = UUID()
        let manifest = RemoteCameraTransferManifest(
            takeID: takeID,
            recordingID: takeID,
            fileName: "camera.mov",
            byteCount: 4_194_304,
            durationSeconds: 12,
            settings: RemoteCameraSettings(
                lens: .wide,
                formatID: "1080p-30",
                frameRate: 30,
                captureProfileID: .highEfficiency
            ),
            format: RemoteCameraFormat(
                id: "1080p-30",
                width: 1920,
                height: 1080,
                frameRates: [30],
                supportsStabilization: true,
                supportsHDR: false,
                supportsCinematicVideo: true
            ),
            captureProfileID: .highEfficiency,
            captureCodecLabel: "HEVC",
            captureFormatLabel: "1920x1080 @ 30 fps",
            deviceStartTime: 100,
            deviceStopTime: 200,
            hostStartTime: 90,
            hostStopTime: 210,
            hostTimelineStartTime: 80,
            estimatedHostStartTime: 95,
            recordingDiagnostics: RemoteCameraRecordingDiagnostics(
                captureFormatID: "1080p-30",
                captureFrameRate: 30,
                captureColorMode: .standard,
                captureStabilizationMode: .cinematic,
                captureRotationDegrees: 90,
                cinematicVideoCaptureEnabled: true,
                cinematicFocusMetadataEnabled: true,
                simulatedAperture: 2.8,
                recordsOrientationAndMirroringChangesAsMetadataTrack: true,
                firstOrderAmbisonicsAudioSupported: true,
                firstOrderAmbisonicsAudioEnabled: true,
                captureWarning: "Cinematic needs more light",
                observedAtDeviceStartTime: 100
            )
        )
        let event = RemoteCameraEvent.transferReady(
            takeID: takeID,
            fileName: "camera.mov",
            byteCount: 4_194_304,
            manifest: manifest
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(RemoteCameraEvent.self, from: data)

        XCTAssertEqual(decoded, event)
        guard case .transferReady(_, _, _, let manifest) = decoded else {
            return XCTFail("Expected transferReady event")
        }
        XCTAssertEqual(manifest.format?.supportsCinematicVideo, true)
        XCTAssertEqual(manifest.recordingDiagnostics?.captureFormatID, "1080p-30")
        XCTAssertEqual(manifest.recordingDiagnostics?.captureFrameRate, 30)
        XCTAssertEqual(manifest.recordingDiagnostics?.captureColorMode, .standard)
        XCTAssertEqual(manifest.recordingDiagnostics?.captureStabilizationMode, .cinematic)
        XCTAssertEqual(manifest.recordingDiagnostics?.captureRotationDegrees, 90)
        XCTAssertEqual(manifest.recordingDiagnostics?.cinematicVideoCaptureEnabled, true)
        XCTAssertEqual(manifest.recordingDiagnostics?.cinematicFocusMetadataEnabled, true)
        XCTAssertEqual(manifest.recordingDiagnostics?.simulatedAperture, 2.8)
        XCTAssertEqual(manifest.recordingDiagnostics?.recordsOrientationAndMirroringChangesAsMetadataTrack, true)
        XCTAssertEqual(manifest.recordingDiagnostics?.firstOrderAmbisonicsAudioSupported, true)
        XCTAssertEqual(manifest.recordingDiagnostics?.firstOrderAmbisonicsAudioEnabled, true)
        XCTAssertEqual(manifest.recordingDiagnostics?.captureWarning, "Cinematic needs more light")
    }

    func testTransferManifestDecodesLegacyPayloadWithoutRecordingDiagnostics() throws {
        let takeID = UUID()
        let data = """
        {
          "takeID": "\(takeID.uuidString)",
          "recordingID": "\(takeID.uuidString)",
          "fileName": "camera.mov",
          "byteCount": 1024,
          "durationSeconds": 2.5,
          "settings": {
            "lens": "wide",
            "frameRate": 30
          }
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(RemoteCameraTransferManifest.self, from: data)

        XCTAssertEqual(manifest.takeID, takeID)
        XCTAssertNil(manifest.recordingDiagnostics)
        XCTAssertEqual(manifest.settings.frameRate, 30)
    }

    func testRemoteCameraSettingsDecodesLegacyPayloadWithAutomaticProfile() throws {
        let data = """
        {
          "lens": "wide",
          "formatID": "1920x1080",
          "frameRate": 30,
          "zoomFactor": 1.2,
          "focusMode": "continuousAuto",
          "focusPosition": 0.5,
          "exposureMode": "continuousAuto",
          "exposureBias": 0,
          "whiteBalanceMode": "continuousAuto",
          "whiteBalanceTemperature": 5500,
          "whiteBalanceTint": 0,
          "stabilizationMode": "auto",
          "torchEnabled": false
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(RemoteCameraSettings.self, from: data)

        XCTAssertEqual(decoded.captureProfileID, .automatic)
        XCTAssertEqual(decoded.colorMode, .standard)
        XCTAssertEqual(decoded.formatID, "1920x1080")
        XCTAssertEqual(decoded.rotationDegrees, RemoteCameraSettings.defaultRotationDegrees)
        XCTAssertEqual(decoded.cinematicVideoEnabled, false)
        XCTAssertNil(decoded.cinematicAperture)
    }

    func testRemoteCameraSettingsNormalizesRotationDegrees() {
        XCTAssertEqual(RemoteCameraSettings().rotationDegrees, 180)
        XCTAssertEqual(RemoteCameraSettings(rotationDegrees: 91).rotationDegrees, 90)
        XCTAssertEqual(RemoteCameraSettings(rotationDegrees: -90).rotationDegrees, 270)
        XCTAssertEqual(RemoteCameraSettings(rotationDegrees: 360).rotationDegrees, 0)
    }

    func testRemoteCameraSettingsResolverClampsToCapabilities() {
        let capabilities = makeResolverCapabilities()
        let resolved = RemoteCameraSettingsResolver.normalized(
            RemoteCameraSettings(
                lens: .telephoto,
                formatID: "4k",
                frameRate: 60,
                captureProfileID: .proRes422,
                zoomFactor: 3,
                focusMode: .manual,
                focusPosition: 2,
                exposureMode: .manual,
                exposureBias: 9,
                iso: 2_000,
                shutterDurationSeconds: 10,
                whiteBalanceMode: .manual,
                whiteBalanceTemperature: 7_000,
                whiteBalanceTint: 4,
                stabilizationMode: .cinematic,
                rotationDegrees: 91,
                torchEnabled: true,
                cinematicVideoEnabled: true,
                cinematicAperture: 20
            ),
            capabilities: capabilities,
            preferredFrameRate: 30
        )

        XCTAssertEqual(resolved.lens, .wide)
        XCTAssertEqual(resolved.formatID, "1080p")
        XCTAssertEqual(resolved.frameRate, 30)
        XCTAssertEqual(resolved.captureProfileID, .automatic)
        XCTAssertEqual(resolved.colorMode, .standard)
        XCTAssertEqual(resolved.zoomFactor, 1)
        XCTAssertEqual(resolved.torchEnabled, false)
        XCTAssertEqual(resolved.focusPosition, 1)
        XCTAssertEqual(resolved.exposureMode, .continuousAuto)
        XCTAssertEqual(resolved.whiteBalanceMode, .continuousAuto)
        XCTAssertEqual(resolved.stabilizationMode, .off)
        XCTAssertEqual(resolved.rotationDegrees, 0)
        XCTAssertEqual(resolved.cinematicVideoEnabled, false)
        XCTAssertNil(resolved.cinematicAperture)
    }

    func testRemoteCameraSettingsResolverKeepsSupportedRotation() {
        var capabilities = makeResolverCapabilities()
        capabilities.supportedRotationDegrees = [0, 90, 180, 270]

        let resolved = RemoteCameraSettingsResolver.normalized(
            RemoteCameraSettings(rotationDegrees: 90),
            capabilities: capabilities,
            preferredFrameRate: 30
        )

        XCTAssertEqual(resolved.rotationDegrees, 90)
    }

    func testRemoteCameraSettingsResolverFiltersProfileFormatsAndAspectRatio() {
        let formats = [
            RemoteCameraFormat(id: "1080p", width: 1920, height: 1080, frameRates: [30], supportsStabilization: false, supportsHDR: false),
            RemoteCameraFormat(id: "4k", width: 3840, height: 2160, frameRates: [30], supportsStabilization: false, supportsHDR: false)
        ]
        let profiles = [
            RemoteCameraCaptureProfile(id: .automatic),
            RemoteCameraCaptureProfile(id: .highEfficiency, supportedFormatIDs: ["4k"])
        ]

        let filtered = RemoteCameraSettingsResolver.formats(formats, supportedBy: .highEfficiency, profiles: profiles)

        XCTAssertEqual(filtered.map(\.id), ["4k"])
        XCTAssertEqual(
            RemoteCameraSettingsResolver.aspectRatio(width: 1920, height: 1080, rotationDegrees: 180),
            9.0 / 16.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            RemoteCameraSettingsResolver.aspectRatio(width: 1920, height: 1080, rotationDegrees: 90),
            16.0 / 9.0,
            accuracy: 0.0001
        )
        XCTAssertTrue(RemoteCameraSettingsResolver.isPortraitRotation(180))
        XCTAssertTrue(RemoteCameraSettingsResolver.isPortraitRotation(0))
        XCTAssertFalse(RemoteCameraSettingsResolver.isPortraitRotation(90))
        XCTAssertFalse(RemoteCameraSettingsResolver.isPortraitRotation(270))
    }

    func testRemoteCameraSettingsResolverFiltersFrameRatesByProfileAndColorMode() {
        let format = RemoteCameraFormat(
            id: "4k",
            width: 3840,
            height: 2160,
            frameRates: [30, 60, 120],
            colorModes: [.standard, .appleLog2],
            colorModeFrameRates: [.standard: [30, 60, 120], .appleLog2: [30, 60]],
            supportsStabilization: false,
            supportsHDR: true
        )
        let profiles = [
            RemoteCameraCaptureProfile(id: .automatic),
            RemoteCameraCaptureProfile(
                id: .proRes422,
                supportedFormatIDs: ["4k"],
                supportedFormatFrameRates: ["4k": [30, 60]]
            )
        ]
        let frameRates = RemoteCameraSettingsResolver.compatibleFrameRates(
            for: format,
            profileID: .proRes422,
            colorMode: .appleLog2,
            profiles: profiles
        )

        XCTAssertEqual(frameRates, [30, 60])

        let resolved = RemoteCameraSettingsResolver.normalized(
            RemoteCameraSettings(
                formatID: "4k",
                frameRate: 120,
                captureProfileID: .proRes422,
                colorMode: .appleLog2
            ),
            capabilities: RemoteCameraCapabilities(
                deviceName: "Alice iPhone",
                supportedLenses: [.wide],
                supportedFormats: [format],
                supportedCaptureProfiles: profiles,
                supportsTorch: false,
                supportsManualFocus: false,
                supportsFocusLock: false,
                supportsManualExposure: false,
                supportsExposureLock: false,
                supportsWhiteBalanceLock: false,
                supportsManualWhiteBalance: false,
                supportedStabilizationModes: [.off],
                minimumExposureBias: -2,
                maximumExposureBias: 2
            ),
            preferredFrameRate: 30
        )

        XCTAssertEqual(resolved.colorMode, .appleLog2)
        XCTAssertEqual(resolved.captureProfileID, .proRes422)
        XCTAssertEqual(resolved.frameRate, 30)
    }

    func testRemoteCameraSettingsResolverUsesLensSpecificFormats() {
        let capabilities = RemoteCameraCapabilities(
            deviceName: "Alice iPhone",
            supportedLenses: [.wide, .telephoto],
            lensCapabilities: [
                makeLensCapabilities(
                    lens: .telephoto,
                    formats: [
                        RemoteCameraFormat(
                            id: "tele-4k",
                            width: 3840,
                            height: 2160,
                            frameRates: [30, 60],
                            supportsStabilization: true,
                            supportsHDR: true
                        )
                    ]
                )
            ],
            supportedFormats: [
                RemoteCameraFormat(
                    id: "wide-1080p",
                    width: 1920,
                    height: 1080,
                    frameRates: [30],
                    supportsStabilization: false,
                    supportsHDR: false
                )
            ],
            supportsTorch: false,
            supportsManualFocus: false,
            supportsFocusLock: false,
            supportsManualExposure: false,
            supportsExposureLock: false,
            supportsWhiteBalanceLock: false,
            supportsManualWhiteBalance: false,
            supportedStabilizationModes: [.off],
            minimumExposureBias: -2,
            maximumExposureBias: 2
        )

        let resolved = RemoteCameraSettingsResolver.normalized(
            RemoteCameraSettings(
                lens: .telephoto,
                formatID: "tele-4k",
                frameRate: 60,
                stabilizationMode: .standard
            ),
            capabilities: capabilities,
            preferredFrameRate: 30
        )

        XCTAssertEqual(resolved.lens, .telephoto)
        XCTAssertEqual(resolved.formatID, "tele-4k")
        XCTAssertEqual(resolved.frameRate, 60)
        XCTAssertEqual(resolved.stabilizationMode, .standard)
    }

    func testRemoteCameraSettingsResolverSelectsCinematicFormatWhenSupportIsKnown() {
        let capabilities = RemoteCameraCapabilities(
            deviceName: "Alice iPhone",
            supportedLenses: [.wide],
            supportedFormats: [
                RemoteCameraFormat(
                    id: "4k",
                    width: 3840,
                    height: 2160,
                    frameRates: [30, 60],
                    colorModes: [.standard, .appleLog2],
                    colorModeFrameRates: [.appleLog2: [30, 60]],
                    supportsStabilization: true,
                    supportsHDR: true,
                    supportsCinematicVideo: false
                ),
                RemoteCameraFormat(
                    id: "1080p-cinematic",
                    width: 1920,
                    height: 1080,
                    frameRates: [30],
                    supportsStabilization: true,
                    supportsHDR: false,
                    supportsCinematicVideo: true
                )
            ],
            supportedCaptureProfiles: [
                RemoteCameraCaptureProfile(id: .automatic),
                RemoteCameraCaptureProfile(
                    id: .highEfficiency,
                    supportedFormatIDs: ["1080p-cinematic"],
                    supportedFormatFrameRates: ["1080p-cinematic": [30]]
                ),
                RemoteCameraCaptureProfile(
                    id: .proRes422,
                    supportedFormatIDs: ["4k"],
                    supportedFormatFrameRates: ["4k": [30, 60]]
                )
            ],
            supportsTorch: false,
            supportsManualFocus: false,
            supportsFocusLock: false,
            supportsManualExposure: false,
            supportsExposureLock: false,
            supportsWhiteBalanceLock: false,
            supportsManualWhiteBalance: false,
            supportedStabilizationModes: [.off],
            minimumExposureBias: -2,
            maximumExposureBias: 2,
            supportsCinematicVideo: true,
            minimumCinematicAperture: 1.4,
            maximumCinematicAperture: 16,
            defaultCinematicAperture: 2.8
        )

        let resolved = RemoteCameraSettingsResolver.normalized(
            RemoteCameraSettings(
                formatID: "4k",
                frameRate: 60,
                captureProfileID: .proRes422,
                colorMode: .appleLog2,
                cinematicVideoEnabled: true,
                cinematicAperture: 2.8
            ),
            capabilities: capabilities,
            preferredFrameRate: 30
        )

        XCTAssertEqual(resolved.formatID, "1080p-cinematic")
        XCTAssertEqual(resolved.frameRate, 30)
        XCTAssertEqual(resolved.captureProfileID, .highEfficiency)
        XCTAssertEqual(resolved.colorMode, .standard)
        XCTAssertEqual(resolved.cinematicVideoEnabled, true)
        XCTAssertEqual(resolved.cinematicAperture, 2.8)
    }

    func testRemoteCameraSettingsResolverFallsBackToAutomaticCinematicProfileWithoutHEVC() {
        let capabilities = RemoteCameraCapabilities(
            deviceName: "Alice iPhone",
            supportedLenses: [.wide],
            supportedFormats: [
                RemoteCameraFormat(
                    id: "1080p-cinematic",
                    width: 1920,
                    height: 1080,
                    frameRates: [30],
                    supportsStabilization: true,
                    supportsHDR: false,
                    supportsCinematicVideo: true
                )
            ],
            supportedCaptureProfiles: [
                RemoteCameraCaptureProfile(id: .automatic),
                RemoteCameraCaptureProfile(id: .highEfficiency, isAvailable: false)
            ],
            supportsTorch: false,
            supportsManualFocus: false,
            supportsFocusLock: false,
            supportsManualExposure: false,
            supportsExposureLock: false,
            supportsWhiteBalanceLock: false,
            supportsManualWhiteBalance: false,
            supportedStabilizationModes: [.off],
            minimumExposureBias: -2,
            maximumExposureBias: 2,
            supportsCinematicVideo: true,
            minimumCinematicAperture: 1.4,
            maximumCinematicAperture: 16,
            defaultCinematicAperture: 2.8
        )

        let resolved = RemoteCameraSettingsResolver.normalized(
            RemoteCameraSettings(
                formatID: "1080p-cinematic",
                frameRate: 30,
                captureProfileID: .proRes422,
                cinematicVideoEnabled: true
            ),
            capabilities: capabilities,
            preferredFrameRate: 30
        )

        XCTAssertEqual(resolved.captureProfileID, .automatic)
        XCTAssertTrue(resolved.cinematicVideoEnabled)
        XCTAssertEqual(resolved.colorMode, .standard)
    }

    func testRemoteCameraSettingsResolverKeepsCinematicWhenFormatSupportIsUnknown() {
        let capabilities = RemoteCameraCapabilities(
            deviceName: "Alice iPhone",
            supportedLenses: [.wide],
            supportedFormats: [
                RemoteCameraFormat(
                    id: "4k",
                    width: 3840,
                    height: 2160,
                    frameRates: [30],
                    supportsStabilization: true,
                    supportsHDR: true
                )
            ],
            supportsTorch: false,
            supportsManualFocus: false,
            supportsFocusLock: false,
            supportsManualExposure: false,
            supportsExposureLock: false,
            supportsWhiteBalanceLock: false,
            supportsManualWhiteBalance: false,
            supportedStabilizationModes: [.off],
            minimumExposureBias: -2,
            maximumExposureBias: 2,
            supportsCinematicVideo: true,
            minimumCinematicAperture: 1.4,
            maximumCinematicAperture: 16,
            defaultCinematicAperture: 2.8
        )

        let resolved = RemoteCameraSettingsResolver.normalized(
            RemoteCameraSettings(
                formatID: "4k",
                frameRate: 30,
                cinematicVideoEnabled: true,
                cinematicAperture: 4
            ),
            capabilities: capabilities,
            preferredFrameRate: 30
        )

        XCTAssertEqual(resolved.formatID, "4k")
        XCTAssertEqual(resolved.frameRate, 30)
        XCTAssertEqual(resolved.cinematicVideoEnabled, true)
        XCTAssertEqual(resolved.cinematicAperture, 4)
    }

    func testRemoteCameraTransferProtocolNormalizesTransferState() {
        let takeID = UUID()

        XCTAssertEqual(RemoteCameraTransferProtocol.clampedResumeOffset(-10, fileSize: 100), 0)
        XCTAssertEqual(RemoteCameraTransferProtocol.clampedResumeOffset(150, fileSize: 100), 100)
        XCTAssertEqual(
            RemoteCameraTransferProtocol.chunkDisposition(offset: 5, receivedByteCount: 5),
            .append
        )
        XCTAssertEqual(
            RemoteCameraTransferProtocol.chunkDisposition(offset: 2, receivedByteCount: 5),
            .alreadyReceived(acknowledgedByteCount: 5)
        )
        XCTAssertEqual(
            RemoteCameraTransferProtocol.chunkDisposition(offset: 8, receivedByteCount: 5),
            .gap(expectedOffset: 5, receivedOffset: 8)
        )
        XCTAssertFalse(RemoteCameraTransferProtocol.isAcknowledgementValid(
            receivedByteCount: 4,
            expectedMinimumByteCount: 5
        ))
        XCTAssertTrue(RemoteCameraTransferProtocol.shouldCompleteImport(
            receivedByteCount: 100,
            expectedByteCount: 100
        ))
        XCTAssertEqual(
            RemoteCameraTransferProtocol.progress(
                takeID: takeID,
                transferredByteCount: 120,
                expectedByteCount: 100
            ),
            RemoteCameraTransferProgress(
                takeID: takeID,
                transferredByteCount: 100,
                expectedByteCount: 100
            )
        )
    }

    func testRemoteCameraCapabilitiesDecodesLegacyPayloadWithAutomaticProfile() throws {
        let data = """
        {
          "deviceName": "Alice iPhone",
          "supportedLenses": ["wide"],
          "supportedFormats": [],
          "supportsTorch": false,
          "supportsManualFocus": false,
          "supportsFocusLock": false,
          "supportsManualExposure": false,
          "supportsExposureLock": false,
          "supportsWhiteBalanceLock": false,
          "supportsManualWhiteBalance": false,
          "supportedStabilizationModes": ["off"],
          "minimumExposureBias": -2,
          "maximumExposureBias": 2
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(RemoteCameraCapabilities.self, from: data)

        XCTAssertEqual(decoded.supportedCaptureProfiles, [RemoteCameraCaptureProfile(id: .automatic)])
        XCTAssertNil(decoded.deviceModelIdentifier)
        XCTAssertEqual(decoded.supportsCinematicVideo, false)
        XCTAssertNil(decoded.minimumCinematicAperture)
    }

    private func makeResolverCapabilities() -> RemoteCameraCapabilities {
        RemoteCameraCapabilities(
            deviceName: "Alice iPhone",
            supportedLenses: [.wide],
            supportedFormats: [
                RemoteCameraFormat(
                    id: "1080p",
                    width: 1920,
                    height: 1080,
                    frameRates: [24, 30],
                    supportsStabilization: false,
                    supportsHDR: false
                )
            ],
            supportedCaptureProfiles: [
                RemoteCameraCaptureProfile(id: .automatic),
                RemoteCameraCaptureProfile(id: .proRes422, isAvailable: false)
            ],
            supportsTorch: false,
            supportsManualFocus: false,
            supportsFocusLock: false,
            supportsManualExposure: false,
            supportsExposureLock: false,
            supportsWhiteBalanceLock: false,
            supportsManualWhiteBalance: false,
            supportedStabilizationModes: [.off],
            supportedRotationDegrees: [0, 180],
            minimumExposureBias: -2,
            maximumExposureBias: 2
        )
    }

    private func makeLensCapabilities(
        lens: RemoteCameraLens,
        formats: [RemoteCameraFormat]
    ) -> RemoteCameraLensCapabilities {
        RemoteCameraLensCapabilities(
            lens: lens,
            supportedFormats: formats,
            supportedCaptureProfiles: [RemoteCameraCaptureProfile(id: .automatic)],
            supportsTorch: false,
            minimumZoomFactor: 1,
            maximumZoomFactor: 1,
            supportsManualFocus: false,
            supportsFocusLock: false,
            supportsManualExposure: false,
            supportsExposureLock: false,
            supportsWhiteBalanceLock: false,
            supportsManualWhiteBalance: false,
            supportedStabilizationModes: [.off, .standard],
            minimumExposureBias: -2,
            maximumExposureBias: 2
        )
    }

    func testRemoteCameraCapabilitiesRoundTripIncludesDeviceModelIdentifier() throws {
        let capabilities = RemoteCameraCapabilities(
            deviceName: "Alice iPhone",
            deviceModelIdentifier: "iPhone15,3",
            supportedLenses: [.wide],
            supportedFormats: [],
            supportsTorch: true,
            supportsManualFocus: false,
            supportsFocusLock: false,
            supportsManualExposure: false,
            supportsExposureLock: false,
            supportsWhiteBalanceLock: false,
            supportsManualWhiteBalance: false,
            supportedStabilizationModes: [.off],
            minimumExposureBias: -2,
            maximumExposureBias: 2,
            supportsCinematicVideo: true,
            minimumCinematicAperture: 1.4,
            maximumCinematicAperture: 16,
            defaultCinematicAperture: 2.8
        )

        let data = try JSONEncoder().encode(capabilities)
        let decoded = try JSONDecoder().decode(RemoteCameraCapabilities.self, from: data)

        XCTAssertEqual(decoded, capabilities)
        XCTAssertEqual(decoded.deviceModelIdentifier, "iPhone15,3")
        XCTAssertEqual(decoded.supportsCinematicVideo, true)
        XCTAssertEqual(decoded.defaultCinematicAperture, 2.8)
    }

    func testTransferCompleteEventRoundTrip() throws {
        let event = RemoteCameraEvent.transferComplete(
            takeID: UUID(),
            byteCount: 4_194_304,
            sha256: "0123456789abcdef"
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(RemoteCameraEvent.self, from: data)

        XCTAssertEqual(decoded, event)
    }

    func testMonitorFrameEventRoundTrip() throws {
        let event = RemoteCameraEvent.monitorFrame(
            jpegData: Data([0xff, 0xd8, 0xff, 0xd9]),
            width: 640,
            height: 360
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(RemoteCameraEvent.self, from: data)

        XCTAssertEqual(decoded, event)
    }

    func testMonitorVideoFrameEventRoundTrip() throws {
        let frame = RemoteCameraMonitorVideoFrame(
            codec: .h264,
            data: Data([0, 0, 0, 4, 0x65, 0x88, 0x84, 0x21]),
            width: 640,
            height: 360,
            presentationTimeSeconds: 12.25,
            frameDurationSeconds: 1.0 / 24.0,
            isKeyFrame: true,
            sequenceNumber: 42,
            h264SPS: Data([0x67, 0x42]),
            h264PPS: Data([0x68, 0xce])
        )
        let event = RemoteCameraEvent.monitorVideoFrame(frame)

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(RemoteCameraEvent.self, from: data)

        XCTAssertEqual(decoded, event)
    }

    func testMonitorVideoFrameDecodesLegacyPayloadWithoutFrameDuration() throws {
        let json = """
        {
          "codec": "h264",
          "data": "AAAA",
          "width": 640,
          "height": 360,
          "presentationTimeSeconds": 12.25,
          "isKeyFrame": false,
          "sequenceNumber": 42
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(RemoteCameraMonitorVideoFrame.self, from: json)

        XCTAssertNil(decoded.frameDurationSeconds)
        XCTAssertEqual(decoded.width, 640)
        XCTAssertEqual(decoded.height, 360)
        XCTAssertEqual(decoded.sequenceNumber, 42)
    }

    func testTelemetryRoundTripIncludesTransferProgress() throws {
        let takeID = UUID()
        let telemetry = RemoteCameraTelemetry(
            phase: .transferring,
            elapsedSeconds: 3,
            batteryLevel: 0.8,
            thermalState: "Nominal",
            storageFreeBytes: 1_000_000,
            activeSettings: RemoteCameraSettings(),
            transferProgress: RemoteCameraTransferProgress(
                takeID: takeID,
                transferredByteCount: 50,
                expectedByteCount: 100
            ),
            previewHealth: RemoteCameraPreviewHealth(
                framesSent: 25,
                framesDropped: 1,
                lastFrameAgeSeconds: 0.2,
                isTransferActive: true
            ),
            captureWarning: "Cinematic needs more light"
        )

        let data = try JSONEncoder().encode(telemetry)
        let decoded = try JSONDecoder().decode(RemoteCameraTelemetry.self, from: data)

        XCTAssertEqual(decoded, telemetry)
        XCTAssertEqual(decoded.transferProgress?.fraction, 0.5)
        XCTAssertEqual(decoded.previewHealth?.droppedFrameRatio ?? -1, 1.0 / 26.0, accuracy: 0.0001)
        XCTAssertEqual(decoded.previewHealth?.isTransferActive, true)
        XCTAssertEqual(decoded.previewHealth?.isHealthy, false)
        XCTAssertEqual(decoded.captureWarning, "Cinematic needs more light")
    }

    func testPreviewHealthFlagsHighDroppedFrameRatio() {
        let waiting = RemoteCameraPreviewHealth(
            framesSent: 0,
            framesDropped: 0,
            lastFrameAgeSeconds: nil
        )
        let healthy = RemoteCameraPreviewHealth(
            framesSent: 76,
            framesDropped: 24,
            lastFrameAgeSeconds: 0.2
        )
        let degraded = RemoteCameraPreviewHealth(
            framesSent: 75,
            framesDropped: 25,
            lastFrameAgeSeconds: 0.2
        )
        let stale = RemoteCameraPreviewHealth(
            framesSent: 25,
            framesDropped: 0,
            lastFrameAgeSeconds: 2
        )
        let blockedBeforeFirstFrame = RemoteCameraPreviewHealth(
            framesSent: 0,
            framesDropped: 4,
            lastFrameAgeSeconds: nil
        )

        XCTAssertFalse(waiting.isDroppingFrames)
        XCTAssertFalse(waiting.isStale)
        XCTAssertFalse(waiting.isHealthy)
        XCTAssertTrue(waiting.isWaitingForFirstFrame)
        XCTAssertFalse(healthy.isDroppingFrames)
        XCTAssertFalse(healthy.isStale)
        XCTAssertTrue(healthy.isHealthy)
        XCTAssertFalse(healthy.isWaitingForFirstFrame)
        XCTAssertTrue(degraded.isDroppingFrames)
        XCTAssertFalse(degraded.isStale)
        XCTAssertFalse(degraded.isHealthy)
        XCTAssertFalse(degraded.isWaitingForFirstFrame)
        XCTAssertTrue(stale.isStale)
        XCTAssertFalse(stale.isHealthy)
        XCTAssertFalse(stale.isWaitingForFirstFrame)
        XCTAssertTrue(blockedBeforeFirstFrame.isDroppingFrames)
        XCTAssertTrue(blockedBeforeFirstFrame.isBlockedBeforeFirstFrame)
        XCTAssertFalse(blockedBeforeFirstFrame.isWaitingForFirstFrame)
        XCTAssertFalse(blockedBeforeFirstFrame.isHealthy)
    }

    func testPreviewHealthDecodesLegacyPayloadWithoutTransferState() throws {
        let json = """
        {
          "framesSent": 25,
          "framesDropped": 1,
          "lastFrameAgeSeconds": 0.2
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(RemoteCameraPreviewHealth.self, from: json)

        XCTAssertFalse(decoded.isTransferActive)
        XCTAssertTrue(decoded.isHealthy)
    }

    func testRecordingWarningAccumulatorKeepsUniqueWarningsSeenDuringTake() {
        var accumulator = RemoteCameraRecordingWarningAccumulator()

        accumulator.record(nil)
        accumulator.record("  ")
        accumulator.record("Cinematic needs more light")
        accumulator.record("Cinematic needs more light")
        accumulator.record(" iPhone camera paused due to system pressure ")

        XCTAssertEqual(
            accumulator.captureWarning,
            "Cinematic needs more light. iPhone camera paused due to system pressure"
        )
    }

    func testRecordingWarningAccumulatorIncludesFinalWarning() {
        var accumulator = RemoteCameraRecordingWarningAccumulator(warnings: [
            "Cinematic needs more light"
        ])

        let warning = accumulator.recordingWarning(including: "Camera interrupted")

        XCTAssertEqual(warning, "Cinematic needs more light. Camera interrupted")
        XCTAssertEqual(accumulator.captureWarning, warning)
    }

    func testRecordingWarningAccumulatorMergesExistingWarningWithoutDroppingHistory() {
        XCTAssertEqual(
            RemoteCameraRecordingWarningAccumulator.mergedWarning(
                "Cinematic needs more light. Camera interrupted",
                "Camera interrupted"
            ),
            "Cinematic needs more light. Camera interrupted"
        )
        XCTAssertEqual(
            RemoteCameraRecordingWarningAccumulator.mergedWarning(
                "Cinematic needs more light",
                "Cinematic focus metadata unavailable"
            ),
            "Cinematic needs more light. Cinematic focus metadata unavailable"
        )
    }

    func testRecordingDiagnosticsMergePreservesCinematicFocusMetadataAndWarnings() {
        let base = RemoteCameraRecordingDiagnostics(
            captureFormatID: "1920x1080",
            cinematicVideoCaptureEnabled: true,
            cinematicFocusMetadataEnabled: true,
            captureWarning: "Cinematic needs more light"
        )
        let update = RemoteCameraRecordingDiagnostics(
            captureFrameRate: 30,
            cinematicFocusMetadataEnabled: false,
            simulatedAperture: 2.8,
            recordedVideoCodecTypes: ["HEVC"],
            recordedMetadataTrackCount: 2,
            cinematicAssetVerified: true,
            cinematicTrackCount: 3,
            cinematicDurationSeconds: 1.2,
            captureWarning: "Cinematic focus metadata unavailable",
            observedAtDeviceStartTime: 42
        )

        let merged = base.merging(update)

        XCTAssertEqual(merged.captureFormatID, "1920x1080")
        XCTAssertEqual(merged.captureFrameRate, 30)
        XCTAssertEqual(merged.cinematicVideoCaptureEnabled, true)
        XCTAssertEqual(merged.cinematicFocusMetadataEnabled, false)
        XCTAssertEqual(merged.simulatedAperture, 2.8)
        XCTAssertEqual(merged.recordedVideoCodecTypes, ["HEVC"])
        XCTAssertEqual(merged.recordedMetadataTrackCount, 2)
        XCTAssertEqual(merged.cinematicAssetVerified, true)
        XCTAssertEqual(merged.cinematicTrackCount, 3)
        XCTAssertEqual(merged.cinematicDurationSeconds, 1.2)
        XCTAssertEqual(
            merged.captureWarning,
            "Cinematic needs more light. Cinematic focus metadata unavailable"
        )
        XCTAssertEqual(merged.observedAtDeviceStartTime, 42)
    }

    func testTelemetryDecodesWithoutCaptureWarning() throws {
        let json = """
        {
          "phase": "idle",
          "elapsedSeconds": 0,
          "batteryLevel": null,
          "thermalState": "Nominal",
          "storageFreeBytes": null,
          "activeSettings": {}
        }
        """

        let decoded = try JSONDecoder().decode(RemoteCameraTelemetry.self, from: Data(json.utf8))

        XCTAssertNil(decoded.captureWarning)
        XCTAssertEqual(decoded.activeSettings.frameRate, 30)
    }
}

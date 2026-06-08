import BlitzRecorderCore
import BlitzRecorderTransport
@testable import BlitzRecorderApp
import XCTest

final class RemoteIPhoneCameraStateTests: XCTestCase {
    func testAutomaticSelectionChoosesOnlyDiscoveredIPhoneWhenCameraHasNoExplicitSelection() {
        var state = RemoteIPhoneCameraState()
        let service = DiscoveredBonjourService.directTCP(host: "192.168.1.10", port: 49152)
        _ = state.replaceDiscoveredServices([service])
        var settings = RecordingSettings()
        settings.selectedCameraID = nil

        XCTAssertEqual(state.automaticSelection(settings: settings)?.id, service.id)
    }

    func testAutomaticSelectionChoosesSingleTrustedIPhoneFromMultipleDevices() {
        var state = RemoteIPhoneCameraState()
        let trusted = DiscoveredBonjourService.directTCP(host: "192.168.1.10", port: 49152)
        let untrusted = DiscoveredBonjourService.directTCP(host: "192.168.1.11", port: 49153)
        _ = state.replaceDiscoveredServices([trusted, untrusted])
        var settings = RecordingSettings()
        settings.selectedCameraID = nil
        settings.trustedRemoteCameraServiceIDs = [trusted.id]

        XCTAssertEqual(state.automaticSelection(settings: settings)?.id, trusted.id)
    }

    func testAutomaticSelectionDoesNotOverrideExplicitLocalCamera() {
        var state = RemoteIPhoneCameraState()
        let service = DiscoveredBonjourService.directTCP(host: "192.168.1.10", port: 49152)
        _ = state.replaceDiscoveredServices([service])
        var settings = RecordingSettings()
        settings.selectedCameraID = "local-camera"

        XCTAssertNil(state.automaticSelection(settings: settings))
    }

    func testAutomaticSelectionSkipsAmbiguousUntrustedIPhones() {
        var state = RemoteIPhoneCameraState()
        let first = DiscoveredBonjourService.directTCP(host: "192.168.1.10", port: 49152)
        let second = DiscoveredBonjourService.directTCP(host: "192.168.1.11", port: 49153)
        _ = state.replaceDiscoveredServices([first, second])
        var settings = RecordingSettings()
        settings.selectedCameraID = nil

        XCTAssertNil(state.automaticSelection(settings: settings))
    }

    func testSelectedCapabilitiesUsesSavedLensSpecificCapabilities() {
        var state = RemoteIPhoneCameraState()
        let service = DiscoveredBonjourService.directTCP(host: "192.168.1.10", port: 49152)
        _ = state.replaceDiscoveredServices([service])
        state.setCapabilities(makeCapabilities(), for: service.id)
        var settings = RecordingSettings()
        settings.selectedCameraID = RemoteCameraProviderID.make(for: service.id)
        settings.remoteCameraSettingsByServiceID[service.id] = RemoteCameraSettings(
            lens: .telephoto,
            formatID: "wide-4k"
        )

        let selectedCapabilities = state.selectedCapabilities(settings: settings) { proposedSettings, _ in
            var normalizedSettings = proposedSettings
            normalizedSettings.formatID = "tele-1080"
            return normalizedSettings
        }

        XCTAssertEqual(selectedCapabilities?.supportedFormats.map(\.id), ["tele-1080"])
        XCTAssertEqual(selectedCapabilities?.maximumZoomFactor, 6)
    }

    func testSelectedStatusUsesPreviewHealthWhenTransferSuspendsLiveView() {
        var state = RemoteIPhoneCameraState()
        let service = DiscoveredBonjourService.directTCP(host: "192.168.1.10", port: 49152)
        _ = state.replaceDiscoveredServices([service])
        var settings = RecordingSettings()
        settings.selectedCameraID = RemoteCameraProviderID.make(for: service.id)
        state.setTelemetry(
            RemoteCameraTelemetry(
                phase: .transferring,
                elapsedSeconds: 3,
                batteryLevel: nil,
                thermalState: "Nominal",
                storageFreeBytes: nil,
                activeSettings: RemoteCameraSettings(),
                previewHealth: RemoteCameraPreviewHealth(
                    framesSent: 0,
                    framesDropped: 0,
                    lastFrameAgeSeconds: nil,
                    isTransferActive: true
                )
            ),
            for: service.id
        )

        let status = state.selectedStatus(settings: settings) { health in
            health.isTransferActive ? "Importing iPhone video" : "Unexpected"
        }

        XCTAssertEqual(status, "Importing iPhone video")
    }

    func testSelectedStatusUsesPreviewHealthWhenLiveViewDropsFrames() {
        var state = RemoteIPhoneCameraState()
        let service = DiscoveredBonjourService.directTCP(host: "192.168.1.10", port: 49152)
        _ = state.replaceDiscoveredServices([service])
        var settings = RecordingSettings()
        settings.selectedCameraID = RemoteCameraProviderID.make(for: service.id)
        state.setTelemetry(
            RemoteCameraTelemetry(
                phase: .recording,
                elapsedSeconds: 3,
                batteryLevel: nil,
                thermalState: "Nominal",
                storageFreeBytes: nil,
                activeSettings: RemoteCameraSettings(),
                previewHealth: RemoteCameraPreviewHealth(
                    framesSent: 75,
                    framesDropped: 25,
                    lastFrameAgeSeconds: 0.2
                )
            ),
            for: service.id
        )

        let status = state.selectedStatus(settings: settings) { health in
            health.isDroppingFrames ? "iPhone live view is dropping frames" : "Unexpected"
        }

        XCTAssertEqual(status, "iPhone live view is dropping frames")
    }

    func testSelectedStatusUsesPreviewHealthWhenLiveViewStalls() {
        var state = RemoteIPhoneCameraState()
        let service = DiscoveredBonjourService.directTCP(host: "192.168.1.10", port: 49152)
        _ = state.replaceDiscoveredServices([service])
        var settings = RecordingSettings()
        settings.selectedCameraID = RemoteCameraProviderID.make(for: service.id)
        state.setTelemetry(
            RemoteCameraTelemetry(
                phase: .recording,
                elapsedSeconds: 3,
                batteryLevel: nil,
                thermalState: "Nominal",
                storageFreeBytes: nil,
                activeSettings: RemoteCameraSettings(),
                previewHealth: RemoteCameraPreviewHealth(
                    framesSent: 20,
                    framesDropped: 0,
                    lastFrameAgeSeconds: 2.1
                )
            ),
            for: service.id
        )

        let status = state.selectedStatus(settings: settings) { health in
            health.isStale ? "Live view stalled" : "Unexpected"
        }

        XCTAssertEqual(status, "Live view stalled")
    }

    func testSelectedStatusUsesPreviewHealthWhenLiveViewIsBlockedBeforeFirstFrame() {
        var state = RemoteIPhoneCameraState()
        let service = DiscoveredBonjourService.directTCP(host: "192.168.1.10", port: 49152)
        _ = state.replaceDiscoveredServices([service])
        var settings = RecordingSettings()
        settings.selectedCameraID = RemoteCameraProviderID.make(for: service.id)
        state.setTelemetry(
            RemoteCameraTelemetry(
                phase: .idle,
                elapsedSeconds: 0,
                batteryLevel: nil,
                thermalState: "Nominal",
                storageFreeBytes: nil,
                activeSettings: RemoteCameraSettings(),
                previewHealth: RemoteCameraPreviewHealth(
                    framesSent: 0,
                    framesDropped: 4,
                    lastFrameAgeSeconds: nil
                )
            ),
            for: service.id
        )

        let status = state.selectedStatus(settings: settings) { health in
            health.isBlockedBeforeFirstFrame ? "Live view blocked" : "Unexpected"
        }

        XCTAssertEqual(status, "Live view blocked")
    }

    func testSelectedStatusUsesPreviewHealthBeforeFirstLiveViewFrame() {
        var state = RemoteIPhoneCameraState()
        let service = DiscoveredBonjourService.directTCP(host: "192.168.1.10", port: 49152)
        _ = state.replaceDiscoveredServices([service])
        var settings = RecordingSettings()
        settings.selectedCameraID = RemoteCameraProviderID.make(for: service.id)
        state.setTelemetry(
            RemoteCameraTelemetry(
                phase: .idle,
                elapsedSeconds: 0,
                batteryLevel: nil,
                thermalState: "Nominal",
                storageFreeBytes: nil,
                activeSettings: RemoteCameraSettings(),
                previewHealth: RemoteCameraPreviewHealth(
                    framesSent: 0,
                    framesDropped: 0,
                    lastFrameAgeSeconds: nil
                )
            ),
            for: service.id
        )

        let status = state.selectedStatus(settings: settings) { health in
            health.isWaitingForFirstFrame ? "Waiting for live view" : "Unexpected"
        }

        XCTAssertEqual(status, "Waiting for live view")
    }

    func testSelectedStatusUsesDroppedFrameHealthBeforeFirstSuccessfulLiveViewFrame() {
        var state = RemoteIPhoneCameraState()
        let service = DiscoveredBonjourService.directTCP(host: "192.168.1.10", port: 49152)
        _ = state.replaceDiscoveredServices([service])
        var settings = RecordingSettings()
        settings.selectedCameraID = RemoteCameraProviderID.make(for: service.id)
        state.setTelemetry(
            RemoteCameraTelemetry(
                phase: .recording,
                elapsedSeconds: 3,
                batteryLevel: nil,
                thermalState: "Nominal",
                storageFreeBytes: nil,
                activeSettings: RemoteCameraSettings(),
                previewHealth: RemoteCameraPreviewHealth(
                    framesSent: 0,
                    framesDropped: 4,
                    lastFrameAgeSeconds: nil
                )
            ),
            for: service.id
        )

        let status = state.selectedStatus(settings: settings) { health in
            health.isDroppingFrames ? "iPhone live view is dropping frames" : "Unexpected"
        }

        XCTAssertEqual(status, "iPhone live view is dropping frames")
    }

    func testSelectedStatusSurfacesCinematicCaptureWarning() {
        var state = RemoteIPhoneCameraState()
        let service = DiscoveredBonjourService.directTCP(host: "192.168.1.10", port: 49152)
        _ = state.replaceDiscoveredServices([service])
        var settings = RecordingSettings()
        settings.selectedCameraID = RemoteCameraProviderID.make(for: service.id)
        state.setTelemetry(
            RemoteCameraTelemetry(
                phase: .recording,
                elapsedSeconds: 3,
                batteryLevel: nil,
                thermalState: "Nominal",
                storageFreeBytes: nil,
                activeSettings: RemoteCameraSettings(cinematicVideoEnabled: true),
                captureWarning: "Cinematic needs more light"
            ),
            for: service.id
        )

        let status = state.selectedStatus(settings: settings) { _ in "Unexpected" }

        XCTAssertEqual(status, "Cinematic needs more light")
    }

    func testSelectedStatusSurfacesAutomaticOrientationWarning() {
        var state = RemoteIPhoneCameraState()
        let service = DiscoveredBonjourService.directTCP(host: "192.168.1.10", port: 49152)
        _ = state.replaceDiscoveredServices([service])
        var settings = RecordingSettings()
        settings.selectedCameraID = RemoteCameraProviderID.make(for: service.id)
        state.setTelemetry(
            RemoteCameraTelemetry(
                phase: .idle,
                elapsedSeconds: 0,
                batteryLevel: nil,
                thermalState: "Nominal",
                storageFreeBytes: nil,
                activeSettings: RemoteCameraSettings(usesAutomaticRotation: true),
                captureWarning: "Auto orientation needs the iPhone upright"
            ),
            for: service.id
        )

        let status = state.selectedStatus(settings: settings) { _ in "Unexpected" }

        XCTAssertEqual(status, "Auto orientation needs the iPhone upright")
    }

    func testDeviceSummaryUsesPreviewHealthWhenTransferSuspendsLiveViewBeforeFirstFrame() {
        var state = RemoteIPhoneCameraState()
        let service = DiscoveredBonjourService.directTCP(host: "192.168.1.10", port: 49152)
        _ = state.replaceDiscoveredServices([service])
        var settings = RecordingSettings()
        settings.selectedCameraID = RemoteCameraProviderID.make(for: service.id)
        state.setTelemetry(
            RemoteCameraTelemetry(
                phase: .transferring,
                elapsedSeconds: 3,
                batteryLevel: nil,
                thermalState: "Nominal",
                storageFreeBytes: nil,
                activeSettings: RemoteCameraSettings(),
                previewHealth: RemoteCameraPreviewHealth(
                    framesSent: 0,
                    framesDropped: 0,
                    lastFrameAgeSeconds: nil,
                    isTransferActive: true
                )
            ),
            for: service.id
        )

        let summaries = state.deviceSummaries(settings: settings, marketingName: { _ in nil }) { health in
            health.isTransferActive ? "Importing iPhone video" : "Unexpected"
        }

        XCTAssertEqual(summaries.first?.status, "Importing iPhone video")
    }

    func testDeviceSummaryUsesPreviewHealthWhenLiveViewDropsFrames() {
        var state = RemoteIPhoneCameraState()
        let service = DiscoveredBonjourService.directTCP(host: "192.168.1.10", port: 49152)
        _ = state.replaceDiscoveredServices([service])
        var settings = RecordingSettings()
        settings.selectedCameraID = RemoteCameraProviderID.make(for: service.id)
        state.setTelemetry(
            RemoteCameraTelemetry(
                phase: .recording,
                elapsedSeconds: 3,
                batteryLevel: nil,
                thermalState: "Nominal",
                storageFreeBytes: nil,
                activeSettings: RemoteCameraSettings(),
                previewHealth: RemoteCameraPreviewHealth(
                    framesSent: 75,
                    framesDropped: 25,
                    lastFrameAgeSeconds: 0.2
                )
            ),
            for: service.id
        )

        let summaries = state.deviceSummaries(settings: settings, marketingName: { _ in nil }) { health in
            health.isDroppingFrames ? "iPhone live view is dropping frames" : "Unexpected"
        }

        XCTAssertEqual(summaries.first?.status, "iPhone live view is dropping frames")
    }

    func testDeviceSummaryUsesDroppedFrameHealthBeforeFirstSuccessfulLiveViewFrame() {
        var state = RemoteIPhoneCameraState()
        let service = DiscoveredBonjourService.directTCP(host: "192.168.1.10", port: 49152)
        _ = state.replaceDiscoveredServices([service])
        var settings = RecordingSettings()
        settings.selectedCameraID = RemoteCameraProviderID.make(for: service.id)
        state.setTelemetry(
            RemoteCameraTelemetry(
                phase: .recording,
                elapsedSeconds: 3,
                batteryLevel: nil,
                thermalState: "Nominal",
                storageFreeBytes: nil,
                activeSettings: RemoteCameraSettings(),
                previewHealth: RemoteCameraPreviewHealth(
                    framesSent: 0,
                    framesDropped: 4,
                    lastFrameAgeSeconds: nil
                )
            ),
            for: service.id
        )

        let summaries = state.deviceSummaries(settings: settings, marketingName: { _ in nil }) { health in
            health.isDroppingFrames ? "iPhone live view is dropping frames" : "Unexpected"
        }

        XCTAssertEqual(summaries.first?.status, "iPhone live view is dropping frames")
    }

    func testDeviceSummaryUsesPreviewHealthWhenLiveViewStalls() {
        var state = RemoteIPhoneCameraState()
        let service = DiscoveredBonjourService.directTCP(host: "192.168.1.10", port: 49152)
        _ = state.replaceDiscoveredServices([service])
        var settings = RecordingSettings()
        settings.selectedCameraID = RemoteCameraProviderID.make(for: service.id)
        state.setTelemetry(
            RemoteCameraTelemetry(
                phase: .recording,
                elapsedSeconds: 3,
                batteryLevel: nil,
                thermalState: "Nominal",
                storageFreeBytes: nil,
                activeSettings: RemoteCameraSettings(),
                previewHealth: RemoteCameraPreviewHealth(
                    framesSent: 20,
                    framesDropped: 0,
                    lastFrameAgeSeconds: 2.1
                )
            ),
            for: service.id
        )

        let summaries = state.deviceSummaries(settings: settings, marketingName: { _ in nil }) { health in
            health.isStale ? "Live view stalled" : "Unexpected"
        }

        XCTAssertEqual(summaries.first?.status, "Live view stalled")
    }

    func testDeviceSummaryUsesPreviewHealthWhenLiveViewIsBlockedBeforeFirstFrame() {
        var state = RemoteIPhoneCameraState()
        let service = DiscoveredBonjourService.directTCP(host: "192.168.1.10", port: 49152)
        _ = state.replaceDiscoveredServices([service])
        var settings = RecordingSettings()
        settings.selectedCameraID = RemoteCameraProviderID.make(for: service.id)
        state.setTelemetry(
            RemoteCameraTelemetry(
                phase: .idle,
                elapsedSeconds: 0,
                batteryLevel: nil,
                thermalState: "Nominal",
                storageFreeBytes: nil,
                activeSettings: RemoteCameraSettings(),
                previewHealth: RemoteCameraPreviewHealth(
                    framesSent: 0,
                    framesDropped: 4,
                    lastFrameAgeSeconds: nil
                )
            ),
            for: service.id
        )

        let summaries = state.deviceSummaries(settings: settings, marketingName: { _ in nil }) { health in
            health.isBlockedBeforeFirstFrame ? "Live view blocked" : "Unexpected"
        }

        XCTAssertEqual(summaries.first?.status, "Live view blocked")
    }

    func testDeviceSummarySurfacesCinematicCaptureWarning() {
        var state = RemoteIPhoneCameraState()
        let service = DiscoveredBonjourService.directTCP(host: "192.168.1.10", port: 49152)
        _ = state.replaceDiscoveredServices([service])
        var settings = RecordingSettings()
        settings.selectedCameraID = RemoteCameraProviderID.make(for: service.id)
        state.setTelemetry(
            RemoteCameraTelemetry(
                phase: .recording,
                elapsedSeconds: 3,
                batteryLevel: nil,
                thermalState: "Nominal",
                storageFreeBytes: nil,
                activeSettings: RemoteCameraSettings(cinematicVideoEnabled: true),
                captureWarning: "Cinematic needs more light"
            ),
            for: service.id
        )

        let summaries = state.deviceSummaries(settings: settings, marketingName: { _ in nil }) { _ in
            "Unexpected"
        }

        XCTAssertEqual(summaries.first?.status, "Cinematic needs more light")
    }

    private func makeCapabilities() -> RemoteCameraCapabilities {
        RemoteCameraCapabilities(
            deviceName: "iPhone",
            deviceModelIdentifier: "iPhone18,2",
            supportedLenses: [.wide, .telephoto],
            lensCapabilities: [
                makeLensCapabilities(
                    lens: .wide,
                    formatID: "wide-4k",
                    maximumZoomFactor: 3,
                    supportsCinematicVideo: true
                ),
                makeLensCapabilities(
                    lens: .telephoto,
                    formatID: "tele-1080",
                    maximumZoomFactor: 6,
                    supportsCinematicVideo: false
                )
            ],
            supportedFormats: [
                RemoteCameraFormat(
                    id: "wide-4k",
                    width: 3840,
                    height: 2160,
                    frameRates: [30],
                    supportsStabilization: true,
                    supportsHDR: true
                )
            ],
            supportsTorch: false,
            supportsManualFocus: true,
            supportsFocusLock: true,
            supportsManualExposure: true,
            supportsExposureLock: true,
            supportsWhiteBalanceLock: true,
            supportsManualWhiteBalance: true,
            supportedStabilizationModes: [.off, .auto],
            minimumExposureBias: -2,
            maximumExposureBias: 2
        )
    }

    private func makeLensCapabilities(
        lens: RemoteCameraLens,
        formatID: String,
        maximumZoomFactor: Double,
        supportsCinematicVideo: Bool
    ) -> RemoteCameraLensCapabilities {
        RemoteCameraLensCapabilities(
            lens: lens,
            supportedFormats: [
                RemoteCameraFormat(
                    id: formatID,
                    width: 1920,
                    height: 1080,
                    frameRates: [30],
                    supportsStabilization: true,
                    supportsHDR: true
                )
            ],
            supportedCaptureProfiles: [RemoteCameraCaptureProfile(id: .automatic)],
            supportsTorch: false,
            minimumZoomFactor: 1,
            maximumZoomFactor: maximumZoomFactor,
            supportsManualFocus: true,
            supportsFocusLock: true,
            supportsManualExposure: true,
            supportsExposureLock: true,
            supportsWhiteBalanceLock: true,
            supportsManualWhiteBalance: true,
            supportedStabilizationModes: [.off, .auto],
            minimumExposureBias: -2,
            maximumExposureBias: 2,
            supportsCinematicVideo: supportsCinematicVideo
        )
    }
}

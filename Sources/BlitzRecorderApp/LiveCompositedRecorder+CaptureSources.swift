import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

private struct CaptureSessionObservationRequest {
    let session: AVCaptureSession
    let source: CaptureSource
}

extension LiveCompositedRecorder {
    func applyScreenCaptureUpdate(
        settings: RecordingSettings,
        pickedFilter: SCContentFilter?,
        screenStream: SCStream
    ) async throws -> (display: SCDisplay?, geometry: ScreenSourceGeometry) {

        let configuration: SCStreamConfiguration
        let screenSourceGeometry: ScreenSourceGeometry
        let display: SCDisplay?
        if let pickedFilter {
            display = nil
            screenSourceGeometry = ScreenCaptureGeometry.screenSourceGeometry(for: settings, pickedFilter: pickedFilter)
            configuration = screenStreamConfiguration(
                settings: settings,
                screenSourceGeometry: screenSourceGeometry,
                sourceRect: ScreenCaptureGeometry.pickedSourceRect(request: .init(
                    settings: settings,
                    filter: pickedFilter
                ))
            )
            try await screenStream.updateContentFilter(pickedFilter)
        } else {
            let content = try await SCShareableContent.current
            let source = try ScreenCaptureGeometry.screenSource(for: settings, content: content)
            display = source.display
            screenSourceGeometry = source.geometry
            configuration = screenStreamConfiguration(
                settings: settings,
                screenSourceGeometry: screenSourceGeometry,
                sourceRect: source.sourceRect
            )
            try await screenStream.updateContentFilter(source.filter)
        }

        try await screenStream.updateConfiguration(configuration)
        return (display, screenSourceGeometry)
    }

    func startScreenStream(settings: RecordingSettings, filter pickedFilter: SCContentFilter?) async throws -> ScreenSourceGeometry {
        let filter: SCContentFilter
        let sourceRect: CGRect?
        let screenSourceGeometry: ScreenSourceGeometry
        if let pickedFilter {
            self.pickedScreenFilter = pickedFilter
            screenDisplay = nil
            filter = pickedFilter
            screenSourceGeometry = ScreenCaptureGeometry.screenSourceGeometry(for: settings, pickedFilter: pickedFilter)
            sourceRect = ScreenCaptureGeometry.pickedSourceRect(request: .init(
                settings: settings,
                filter: pickedFilter
            ))
        } else {
            let content = try await SCShareableContent.current
            let source = try ScreenCaptureGeometry.screenSource(for: settings, content: content)
            screenDisplay = source.display
            self.pickedScreenFilter = nil
            filter = source.filter
            screenSourceGeometry = source.geometry
            sourceRect = source.sourceRect
        }

        let configuration = screenStreamConfiguration(
            settings: settings,
            screenSourceGeometry: screenSourceGeometry,
            sourceRect: sourceRect
        )

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        if settings.enabledSources.contains(.screen) {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: screenQueue)
        }
        if settings.enabledSources.contains(.systemAudio) {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: screenQueue)
        }
        try await stream.startCapture()
        screenStream = stream
        return screenSourceGeometry
    }

    private func screenStreamConfiguration(
        settings: RecordingSettings,
        screenSourceGeometry: ScreenSourceGeometry,
        sourceRect: CGRect?
    ) -> SCStreamConfiguration {
        let dimensions = ScreenCaptureGeometry.screenCaptureDimensions(
            for: settings,
            sourceAspectRatio: screenSourceGeometry.aspectRatio()
        )
        let configuration = SCStreamConfiguration()
        configuration.width = dimensions.width
        configuration.height = dimensions.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(settings.framesPerSecond))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 6
        configuration.showsCursor = settings.includeCursor
        if #available(macOS 15.0, *) {
            configuration.showMouseClicks = true
        }
        configuration.capturesAudio = settings.enabledSources.contains(.systemAudio)
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        if let sourceRect {
            configuration.sourceRect = sourceRect
        }
        configuration.streamName = "BlitzRecorder Live Compositor"
        return configuration
    }

    func startCamera(settings: RecordingSettings) throws {
        guard let device = selectedCamera(settings: settings) else {
            throw RecorderError.noCamera
        }

        let session = AVCaptureSession()
        session.beginConfiguration()
        LocalCameraSessionConfiguration.configurePreset(on: session)

        LocalCameraSessionConfiguration.configure(.init(
            device: device,
            fps: settings.framesPerSecond,
            logPrefix: "Live compositor",
            cameraIsRunningSomewhere: LocalCameraUsage.isRunningSomewhere(device)
        ))
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw RecorderError.noCamera
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: cameraQueue)
        guard session.canAddOutput(output) else {
            throw RecorderError.writerNotReady
        }
        session.addOutput(output)
        session.commitConfiguration()

        cameraSession = session
        observeCaptureSession(.init(session: session, source: .camera))
        cameraQueue.async {
            session.startRunning()
        }
    }

    func startMicrophone(settings: RecordingSettings) throws {
        guard let device = MicrophoneDeviceSelection.selectedMicrophone(settings: settings) else {
            throw RecorderError.microphoneUnavailable
        }

        let session = AVCaptureSession()
        session.beginConfiguration()
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw RecorderError.microphoneUnavailable
        }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: microphoneQueue)
        guard session.canAddOutput(output) else {
            throw RecorderError.writerNotReady
        }
        session.addOutput(output)
        session.commitConfiguration()

        microphoneSession = session
        microphoneQueue.async {
            session.startRunning()
        }
    }

    private func selectedCamera(settings: RecordingSettings) -> AVCaptureDevice? {
        LocalCameraSessionConfiguration.selectedCamera(settings: settings)
    }

    private func observeCaptureSession(_ request: CaptureSessionObservationRequest) {
        let center = NotificationCenter.default
        captureSessionObservers.append(center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: request.session,
            queue: nil
        ) { [weak self] notification in
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error
                ?? RecorderError.mediaWriteFailed("\(request.source.rawValue) session failed.")
            self?.reportCaptureFailure(ActiveCaptureFailure(source: request.source, error: error))
        })
        captureSessionObservers.append(center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: request.session,
            queue: nil
        ) { [weak self] _ in
            self?.reportCaptureFailure(ActiveCaptureFailure(
                source: request.source,
                error: RecorderError.mediaWriteFailed("\(request.source.rawValue) capture was interrupted.")
            ))
        })
    }
}

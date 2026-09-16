import AppKit
import BlitzRecorderCore
import CoreMedia
import Foundation

extension RecorderViewModel {
    func setRemoteCameraLens(_ lens: RemoteCameraLens) {
        coordinator.setRemoteCameraLens(lens)
        syncSettings()
    }

    func setRemoteCameraFormat(id: String?, frameRate: Int) {
        coordinator.setRemoteCameraFormat(id: id, frameRate: frameRate)
        syncSettings()
    }

    func setRemoteCameraCaptureProfile(_ profileID: RemoteCameraCaptureProfileID) {
        coordinator.setRemoteCameraCaptureProfile(profileID)
        syncSettings()
    }

    func setRemoteCameraColorMode(_ colorMode: RemoteCameraColorMode) {
        coordinator.setRemoteCameraColorMode(colorMode)
        syncSettings()
    }

    func setRemoteCameraCinematicVideoEnabled(_ enabled: Bool) {
        coordinator.setRemoteCameraCinematicVideoEnabled(enabled)
        syncSettings()
    }

    func setRemoteCameraCinematicAperture(_ aperture: Double) {
        coordinator.setRemoteCameraCinematicAperture(aperture)
        syncSettings()
    }

    func setRemoteCameraFocusMode(_ mode: RemoteCameraFocusMode) {
        coordinator.setRemoteCameraFocusMode(mode)
        syncSettings()
    }

    func setRemoteCameraFocusPosition(_ position: Double) {
        coordinator.setRemoteCameraFocusPosition(position)
        syncSettings()
    }

    func setRemoteCameraExposureMode(_ mode: RemoteCameraExposureMode) {
        coordinator.setRemoteCameraExposureMode(mode)
        syncSettings()
    }

    func setRemoteCameraExposureBias(_ bias: Double) {
        coordinator.setRemoteCameraExposureBias(bias)
        syncSettings()
    }

    func resetRemoteCameraExposureBias() {
        coordinator.resetRemoteCameraExposureBias()
        syncSettings()
    }

    func setRemoteCameraISO(_ iso: Double?) {
        coordinator.setRemoteCameraISO(iso)
        syncSettings()
    }

    func setRemoteCameraShutterDuration(_ seconds: Double?) {
        coordinator.setRemoteCameraShutterDuration(seconds)
        syncSettings()
    }

    func setRemoteCameraWhiteBalanceMode(_ mode: RemoteCameraWhiteBalanceMode) {
        coordinator.setRemoteCameraWhiteBalanceMode(mode)
        syncSettings()
    }

    func setRemoteCameraWhiteBalance(temperature: Double, tint: Double) {
        coordinator.setRemoteCameraWhiteBalance(temperature: temperature, tint: tint)
        syncSettings()
    }

    func resetRemoteCameraImageSettings() {
        coordinator.resetRemoteCameraImageSettings()
        syncSettings()
    }

    func setRemoteCameraStabilizationMode(_ mode: RemoteCameraStabilizationMode) {
        coordinator.setRemoteCameraStabilizationMode(mode)
        syncSettings()
    }

    func setRemoteCameraAutomaticRotation(_ enabled: Bool) {
        coordinator.setRemoteCameraAutomaticRotation(enabled)
        remoteCameraRefreshToken += 1
        syncSettings()
        refreshRemoteCameraPreviewAspectRatioForCurrentFrame()
    }

    func setRemoteCameraRotationDegrees(_ degrees: Int) {
        coordinator.setRemoteCameraRotationDegrees(degrees)
        remoteCameraRefreshToken += 1
        syncSettings()
        refreshRemoteCameraPreviewAspectRatioForCurrentFrame()
    }

    func resetRemoteCameraSettings() {
        coordinator.resetRemoteCameraSettings()
        remoteCameraRefreshToken += 1
        syncSettings()
        refreshRemoteCameraPreviewAspectRatioForCurrentFrame()
    }

    @discardableResult
    func applyRemoteCameraPreviewImage(_ image: CGImage) -> CGFloat {
        let frame = noteRemoteCameraPreviewFrame(
            width: image.width,
            height: image.height
        )
        remoteCameraPreviewSurface.setPreviewImage(image, sourceAspectRatio: frame.aspectRatio)
        return frame.aspectRatio
    }

    @discardableResult
    func applyRemoteCameraPreviewSampleBuffer(_ sampleBuffer: CMSampleBuffer, width: Int, height: Int) -> CGFloat {
        let frame = noteRemoteCameraPreviewFrame(width: width, height: height)
        remoteCameraPreviewSurface.enqueuePreviewSampleBuffer(
            sampleBuffer,
            width: width,
            height: height,
            sourceAspectRatio: frame.aspectRatio
        )
        return frame.aspectRatio
    }

    func clearRemoteCameraPreview(message: String) {
        remoteCameraPreviewSurface.setMessage(message)
        hasRemoteCameraPreviewImage = false
        remoteCameraPreviewFrameSize = nil
    }

    @discardableResult
    func noteRemoteCameraPreviewFrame(width: Int, height: Int) -> RemoteCameraPreviewFrame {
        let frame = RemoteCameraPreviewFrame(
            width: width,
            height: height,
            rotationDegrees: selectedRemoteCameraRotationDegrees
        )
        remoteCameraPreviewFrameSize = frame.size
        remoteCameraPreviewAspectRatio = frame.aspectRatio
        hasRemoteCameraPreviewImage = true
        return frame
    }

    func refreshRemoteCameraPreviewAspectRatioForCurrentFrame() {
        guard let remoteCameraPreviewFrameSize else { return }
        let aspectRatio = RemoteCameraPreviewGeometry.displayAspectRatio(
            width: remoteCameraPreviewFrameSize.width,
            height: remoteCameraPreviewFrameSize.height,
            rotationDegrees: selectedRemoteCameraRotationDegrees
        )
        remoteCameraPreviewAspectRatio = aspectRatio
        remoteCameraPreviewSurface.setSourceAspectRatio(aspectRatio)
    }

    func connectDirectRemoteCamera() {
        coordinator.connectDirectRemoteCamera(
            host: directRemoteCameraHost,
            portString: directRemoteCameraPort
        )
        syncSettings()
        availableCameras = coordinator.availableCameras()
    }

    var remoteTransferProgress: RemoteCameraTransferProgress? {
        guard selectedRemoteCameraTelemetry?.phase == .transferring else { return nil }
        return selectedRemoteCameraTelemetry?.transferProgress
    }

    func byteProgressLabel(_ progress: RemoteCameraTransferProgress) -> String {
        let transferred = ByteCountFormatter.string(
            fromByteCount: progress.transferredByteCount,
            countStyle: .file
        )
        let expected = ByteCountFormatter.string(
            fromByteCount: progress.expectedByteCount,
            countStyle: .file
        )
        return "\(transferred) of \(expected)"
    }

}

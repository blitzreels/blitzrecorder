import AppKit
import AVFoundation
import BlitzRecorderCore
import CoreMedia
import Foundation
import os
import ScreenCaptureKit

@MainActor
extension RecorderCoordinator {
    func setCamera(id: String?) {
        remoteCamera.selectCamera(id: id)
    }

    func connectDirectRemoteCamera(host: String, portString: String) {
        remoteCamera.connectDirect(host: host, portString: portString)
    }

    var isRemoteCameraSelected: Bool {
        remoteCamera.isRemoteCameraSelected()
    }

    func selectedRemoteCameraName() -> String? {
        remoteCamera.selectedName()
    }

    func selectedRemoteCameraStatus() -> String? {
        remoteCamera.selectedStatus()
    }

    func selectedRemoteCameraConnectionState() -> RemoteCameraConnectionState? {
        remoteCamera.selectedConnectionState()
    }

    func selectedRemoteCameraDeviceDescription() -> String {
        remoteCamera.selectedDeviceDescription()
    }

    func selectedRemoteCameraCapabilities() -> RemoteCameraCapabilities? {
        remoteCamera.selectedCapabilities()
    }

    func selectedRemoteCameraTelemetry() -> RemoteCameraTelemetry? {
        remoteCamera.selectedTelemetry()
    }

    func remoteCameraDeviceSummaries() -> [RemoteCameraDeviceSummary] {
        remoteCamera.deviceSummaries()
    }

    func setRemoteCameraLens(_ lens: RemoteCameraLens) {
        remoteCamera.applySettingsIntent(.lens(lens))
    }

    func setRemoteCameraFormat(id: String?, frameRate: Int) {
        remoteCamera.applySettingsIntent(.format(id: id, frameRate: frameRate))
    }

    func setRemoteCameraCaptureProfile(_ profileID: RemoteCameraCaptureProfileID) {
        remoteCamera.applySettingsIntent(.captureProfile(profileID))
    }

    func setRemoteCameraColorMode(_ colorMode: RemoteCameraColorMode) {
        remoteCamera.applySettingsIntent(.colorMode(colorMode))
    }

    func setRemoteCameraCinematicVideoEnabled(_ enabled: Bool) {
        remoteCamera.applySettingsIntent(.cinematicVideoEnabled(enabled))
    }

    func setRemoteCameraCinematicAperture(_ aperture: Double) {
        remoteCamera.applySettingsIntent(.cinematicAperture(aperture))
    }

    func setRemoteCameraFocusMode(_ mode: RemoteCameraFocusMode) {
        remoteCamera.applySettingsIntent(.focusMode(mode))
    }

    func setRemoteCameraFocusPosition(_ position: Double) {
        remoteCamera.applySettingsIntent(.focusPosition(position))
    }

    func setRemoteCameraExposureMode(_ mode: RemoteCameraExposureMode) {
        remoteCamera.applySettingsIntent(.exposureMode(mode))
    }

    func setRemoteCameraExposureBias(_ bias: Double) {
        remoteCamera.applySettingsIntent(.exposureBias(bias))
    }

    func resetRemoteCameraExposureBias() {
        remoteCamera.applySettingsIntent(.resetExposureBias)
    }

    func setRemoteCameraISO(_ iso: Double?) {
        remoteCamera.applySettingsIntent(.iso(iso))
    }

    func setRemoteCameraShutterDuration(_ seconds: Double?) {
        remoteCamera.applySettingsIntent(.shutterDuration(seconds))
    }

    func setRemoteCameraWhiteBalanceMode(_ mode: RemoteCameraWhiteBalanceMode) {
        remoteCamera.applySettingsIntent(.whiteBalanceMode(mode))
    }

    func setRemoteCameraWhiteBalance(temperature: Double, tint: Double) {
        remoteCamera.applySettingsIntent(.whiteBalance(temperature: temperature, tint: tint))
    }

    func setRemoteCameraStabilizationMode(_ mode: RemoteCameraStabilizationMode) {
        remoteCamera.applySettingsIntent(.stabilizationMode(mode))
    }

    func setRemoteCameraAutomaticRotation(_ enabled: Bool) {
        remoteCamera.applySettingsIntent(.automaticRotation(enabled))
    }

    func setRemoteCameraRotationDegrees(_ degrees: Int) {
        remoteCamera.applySettingsIntent(.rotationDegrees(degrees))
    }

    func resetRemoteCameraImageSettings() {
        remoteCamera.applySettingsIntent(.resetImageSettings)
    }

    func resetRemoteCameraSettings() {
        remoteCamera.resetSettings()
    }

    func remoteCameraOptions() -> [SourceOption] {
        remoteCamera.cameraOptions()
    }

    func startRemoteCameraDiscoveryIfNeeded() {
        remoteCamera.startDiscoveryIfNeeded()
    }

    func requireRemoteCameraConnection() async throws {
        try await remoteCamera.requireConnection()
    }

    func remoteCameraConnectionBlocker() -> PermissionBlocker? {
        remoteCamera.connectionBlocker()
    }

}

import AppKit
import AVFoundation
import BlitzRecorderCore
import CoreMedia
import Foundation
import os
import ScreenCaptureKit

@MainActor
extension RecorderCoordinator {
    func noteScreenSourceAspectRatio(_ aspectRatio: CGFloat) {
        studio.noteScreenSourceAspectRatio(aspectRatio)
    }

    func scenesForCurrentLayout() -> [RecordingSceneDefinition] {
        studio.scenesForCurrentLayout()
    }

    func scenes(for layout: CaptureLayout) -> [RecordingSceneDefinition] {
        studio.scenes(for: layout)
    }

    func layout(ofSceneID id: UUID) -> CaptureLayout? {
        studio.layout(ofSceneID: id)
    }

    func selectedSceneIDForCurrentLayout() -> UUID? {
        studio.selectedSceneIDForCurrentLayout()
    }

    func selectedSceneName() -> String {
        studio.selectedSceneName()
    }

    func selectScene(id: UUID) {
        studio.selectScene(id: id)
    }

    func setLayout(_ layout: CaptureLayout) {
        studio.setLayout(layout)
    }

    func setOutputResolution(_ outputResolution: OutputResolution) {
        studio.setOutputResolution(outputResolution)
    }

    func setOutputVideoFormat(_ outputVideoFormat: OutputVideoFormat) {
        studio.setOutputVideoFormat(outputVideoFormat)
    }

    func setFramesPerSecond(_ framesPerSecond: Int) {
        studio.setFramesPerSecond(framesPerSecond)
    }

    func setCustomVideoBitrate(_ bitrate: Int?) {
        studio.setCustomVideoBitrate(bitrate)
    }

    func setAudioQuality(_ audioQuality: AudioQuality) {
        studio.setAudioQuality(audioQuality)
    }

    func setSourceAudioFormat(_ sourceAudioFormat: SourceAudioFormat) {
        studio.setSourceAudioFormat(sourceAudioFormat)
    }

    func setMicrophoneGain(_ microphoneGain: Double) {
        studio.setMicrophoneGain(microphoneGain)
    }

    func setSystemAudioGain(_ systemAudioGain: Double) {
        studio.setSystemAudioGain(systemAudioGain)
    }

    func setCameraBackgroundRemovalAfterRecording(_ enabled: Bool) {
        studio.setCameraBackgroundRemovalAfterRecording(enabled)
    }

    func setSourceFilesSaved(_ enabled: Bool) {
        studio.setSourceFilesSaved(enabled)
    }

    func setRuleOfThirdsOverlayVisible(_ visible: Bool) {
        studio.setRuleOfThirdsOverlayVisible(visible)
    }

    func setSocialSafeZoneOverlay(_ overlay: SocialVideoSafeZone) {
        studio.setSocialSafeZoneOverlay(overlay)
    }

    func setCursorIncluded(_ included: Bool) {
        studio.setCursorIncluded(included)
    }

    func addSource(_ source: CaptureSource) {
        studio.addSource(source)
    }

    func removeSource(_ source: CaptureSource) {
        studio.removeSource(source)
    }

    func setOutputDirectory(_ url: URL) {
        studio.setOutputDirectory(url)
    }

    func setSourceDirectory(_ url: URL) {
        studio.setSourceDirectory(url)
    }

    func setDisplay(id: String?) {
        studio.setDisplay(id: id)
    }

    func setSceneLayer(
        _ kind: SceneLayerKind,
        frame: CGRect,
        transition: RecordingSceneTransition = .cut
    ) {
        studio.setSceneLayer(kind, frame: frame, transition: transition)
    }

    func setCameraCrop(_ crop: CameraCropControl) {
        studio.setCameraCrop(crop)
    }

    func setCameraCropAmount(_ amount: CGPoint) {
        studio.setCameraCropAmount(amount)
    }

    func setCameraCropPosition(_ position: CGPoint) {
        studio.setCameraCropPosition(position)
    }

    func setCanvasBackgroundStyle(_ style: CanvasBackgroundStyle) {
        studio.setCanvasBackgroundStyle(style)
    }

    func setCanvasBackgroundAnimated(_ animated: Bool) {
        studio.setCanvasBackgroundAnimated(animated)
    }

    func setCanvasPadding(_ padding: CGFloat) {
        studio.setCanvasPadding(padding)
    }

    func setCameraContentMode(_ mode: CameraContentMode) {
        studio.setCameraContentMode(mode)
    }

    func setScreenContentMode(_ mode: CameraContentMode) {
        studio.setScreenContentMode(mode)
    }

    func setCameraFramePadding(_ padding: CGFloat) {
        studio.setCameraFramePadding(padding)
    }

    func setCameraShadowEnabled(_ enabled: Bool) {
        studio.setCameraShadowEnabled(enabled)
    }

    func setSceneLayout(_ sceneLayout: SceneLayout) {
        studio.setSceneLayout(sceneLayout)
    }

    func resetSceneLayout() {
        studio.resetSceneLayout()
    }

    func applyScenePreset(_ preset: ScenePreset) {
        studio.applyScenePreset(preset)
    }

    func setScreenSplitHeight(_ height: CGFloat) {
        studio.setScreenSplitHeight(height)
    }

    func setSideBySideLayout(_ request: SceneLayout.SideBySideRequest) {
        studio.setSideBySideLayout(request)
    }

    func setCameraInset(
        alignment: CameraInsetAlignment,
        shape: CameraInsetShape,
        size: CGFloat
    ) {
        studio.setCameraInset(alignment: alignment, shape: shape, size: size)
    }

    @discardableResult
    func fitScreenToAvailableSlot() -> CGRect {
        studio.fitScreenToAvailableSlot()
    }

    func setSceneLayerOrder(_ order: [SceneLayerKind]) {
        studio.setSceneLayerOrder(order)
    }

    func fitSceneLayer(_ kind: SceneLayerKind, scale: CGFloat = 1) {
        studio.fitSceneLayer(kind, scale: scale)
    }

    func beginScreenCropEditing() {
        studio.beginScreenCropEditing()
    }

    func endScreenCropEditing() {
        studio.endScreenCropEditing()
    }

    func setScreenCrop(_ crop: CGRect?) {
        studio.setScreenCrop(crop)
    }

    func setScreenWindowZoom(_ zoom: CGFloat) {
        studio.setScreenWindowZoom(zoom)
    }

    func clearScreenCrop() {
        studio.clearScreenCrop()
    }

    var allowsSceneChanges: Bool { studio.allowsSceneChanges }
}

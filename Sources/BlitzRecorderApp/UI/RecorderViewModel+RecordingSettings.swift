import Foundation

extension RecorderViewModel {
    func setCanvasBackgroundStyle(_ style: CanvasBackgroundStyle) {
        coordinator.setCanvasBackgroundStyle(style)
        previewStage.canvasBackgroundStyle = coordinator.settings.canvasBackgroundStyle
        previewStage.canvasBackgroundAnimated = coordinator.settings.canvasBackgroundAnimated
        syncSettings()
    }

    func setCanvasBackgroundAnimated(_ animated: Bool) {
        coordinator.setCanvasBackgroundAnimated(animated)
        previewStage.canvasBackgroundAnimated = coordinator.settings.canvasBackgroundAnimated
        syncSettings()
    }

    func setCanvasPadding(_ padding: CGFloat) {
        coordinator.setCanvasPadding(padding)
        syncSettings()
    }

    func setResolution(_ resolution: OutputResolution) {
        coordinator.setOutputResolution(resolution)
        syncSettings()
    }

    func setFormat(_ format: OutputVideoFormat) {
        coordinator.setOutputVideoFormat(format)
        syncSettings()
    }

    func setFrameRate(_ fps: Int) {
        coordinator.setFramesPerSecond(fps)
        syncSettings()
    }

    func setCustomVideoBitrate(_ bitrate: Int?) {
        coordinator.setCustomVideoBitrate(bitrate)
        syncSettings()
    }

    func setAudioQuality(_ quality: AudioQuality) {
        coordinator.setAudioQuality(quality)
        syncSettings()
    }

    func setSourceAudioFormat(_ format: SourceAudioFormat) {
        coordinator.setSourceAudioFormat(format)
        syncSettings()
    }

    func setMicrophoneGain(_ gain: Double) {
        coordinator.setMicrophoneGain(gain)
        syncSettings()
    }

    func setSystemAudioGain(_ gain: Double) {
        coordinator.setSystemAudioGain(gain)
        syncSettings()
    }

    func setCameraBackgroundRemovalAfterRecording(_ enabled: Bool) {
        coordinator.setCameraBackgroundRemovalAfterRecording(enabled)
        syncSettings()
    }

    func setSourceFilesSaved(_ enabled: Bool) {
        coordinator.setSourceFilesSaved(enabled)
        syncSettings()
    }

    func setCursorIncluded(_ included: Bool) {
        coordinator.setCursorIncluded(included)
        syncSettings()
    }

    func setRuleOfThirds(_ enabled: Bool) {
        coordinator.setRuleOfThirdsOverlayVisible(enabled)
        syncSettings()
    }

    func setSocialSafeZoneOverlay(_ overlay: SocialVideoSafeZone) {
        coordinator.setSocialSafeZoneOverlay(overlay)
        syncSettings()
    }

    func setDisplay(_ id: String?) {
        coordinator.setDisplay(id: id)
        syncSettings()
    }
}

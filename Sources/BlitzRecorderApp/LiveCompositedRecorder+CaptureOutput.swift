import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

extension LiveCompositedRecorder {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }

        switch type {
        case .screen:
            guard frameStatus(for: sampleBuffer) == .complete || frameStatus(for: sampleBuffer) == .started,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                return
            }
            lock.lock()
            latestScreenBuffer = pixelBuffer
            lock.unlock()
            publishScreenPreviewFrame(sampleBuffer, imageBuffer: pixelBuffer)
        case .audio:
            writer?.appendAudio(sampleBuffer, source: .systemAudio)
        default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard stream !== intentionallyStoppedScreenStream else { return }
        NSLog("Live compositor screen stream stopped: \(error.localizedDescription)")
        streamError = error
        let recorderError = RecorderError.captureStreamStopped(error.localizedDescription)
        let source: CaptureSource = settings?.enabledSources.contains(.screen) == true
            ? .screen
            : .systemAudio
        reportCaptureFailure(ActiveCaptureFailure(source: source, error: recorderError))
    }

    private func publishScreenPreviewFrame(_ sampleBuffer: CMSampleBuffer, imageBuffer: CVPixelBuffer) {
        guard let onScreenPreviewFrame else { return }

        let now = DispatchTime.now()
        let minimumFrameInterval = 1_000_000_000 / UInt64(60)
        guard now.uptimeNanoseconds - lastScreenPreviewFrameTime.uptimeNanoseconds > minimumFrameInterval else {
            return
        }
        lastScreenPreviewFrameTime = now

        lock.lock()
        let sourceAspectRatio = recordingScene?.screenSourceGeometry.aspectRatio()
            ?? SceneLayout.defaultScreenAspectRatio
        lock.unlock()

        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        Task { @MainActor [onScreenPreviewFrame, sampleBuffer] in
            onScreenPreviewFrame(ScreenPreviewFrame(
                sampleBuffer: sampleBuffer,
                width: width,
                height: height,
                sourceAspectRatio: sourceAspectRatio
            ))
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if output is AVCaptureVideoDataOutput {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            lock.lock()
            latestCameraBuffer = pixelBuffer
            lock.unlock()
            publishCameraPreviewFrame(sampleBuffer)
        } else if output is AVCaptureAudioDataOutput {
            lock.lock()
            hasProducedMicrophoneStartupSample = true
            lock.unlock()
            writer?.appendAudio(sampleBuffer, source: .microphone)
        }
    }

    private func publishCameraPreviewFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        let width = Int(dimensions.width)
        let height = Int(dimensions.height)
        guard width > 0, height > 0 else { return }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0,
           let attachment = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary?.self) {
            CFDictionarySetValue(
                attachment,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }

        DispatchQueue.main.async { [weak self, sampleBuffer] in
            self?.onCameraPreviewSampleBuffer?(sampleBuffer, width, height)
        }
    }

    private func frameStatus(for sampleBuffer: CMSampleBuffer) -> SCFrameStatus {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[SCStreamFrameInfo.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus) else {
            return .complete
        }
        return status
    }
}

import CoreMedia
import ScreenCaptureKit

extension CMSampleBuffer {
    var screenCaptureFrameStatus: SCFrameStatus {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(self, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[SCStreamFrameInfo.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus) else {
            return .complete
        }
        return status
    }
}

import Foundation

struct RemoteCameraDeviceSummary: Equatable, Identifiable {
    var id: String
    var cameraID: String
    var name: String
    var detail: String
    var status: String
    var isSelected: Bool
    var isReady: Bool
    var isTrusted: Bool
    var lensCount: Int?
}

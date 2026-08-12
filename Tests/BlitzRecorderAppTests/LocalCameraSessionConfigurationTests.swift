@testable import BlitzRecorderApp
import AVFoundation
import XCTest

final class LocalCameraSessionConfigurationTests: XCTestCase {
    func testAutomaticCameraUsesMacOSDefaultCamera() throws {
        guard let systemDefault = AVCaptureDevice.default(for: .video) else {
            throw XCTSkip("No macOS default camera is available.")
        }

        let selected = LocalCameraSessionConfiguration.selectedCamera(
            settings: RecordingSettings()
        )

        XCTAssertEqual(selected?.uniqueID, systemDefault.uniqueID)
    }
}

import XCTest
@testable import BlitzRecorderCore

final class RemoteCameraProviderIDTests: XCTestCase {
    func testRoundTripsServiceID() {
        let serviceID = "Alice-iPhone._blitzrecorder-camera._tcp.local."
        let pickerID = RemoteCameraProviderID.make(for: serviceID)

        XCTAssertTrue(RemoteCameraProviderID.isRemote(pickerID))
        XCTAssertEqual(RemoteCameraProviderID.serviceID(from: pickerID), serviceID)
    }

    func testRejectsLocalCameraIDs() {
        XCTAssertFalse(RemoteCameraProviderID.isRemote("local-avcapture-id"))
        XCTAssertNil(RemoteCameraProviderID.serviceID(from: "local-avcapture-id"))
        XCTAssertFalse(RemoteCameraProviderID.isRemote(nil))
    }
}

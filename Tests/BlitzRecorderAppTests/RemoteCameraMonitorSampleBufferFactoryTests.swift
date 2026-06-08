import BlitzRecorderCore
@testable import BlitzRecorderApp
import XCTest

final class RemoteCameraMonitorSampleBufferFactoryTests: XCTestCase {
    func testDecoderResetsWhenMonitorSequenceRestarts() {
        let factory = RemoteCameraMonitorSampleBufferFactory()
        factory.recordAcceptedFrame(makeFrame(sequenceNumber: 12))

        XCTAssertFalse(factory.shouldResetDecoder(for: makeFrame(sequenceNumber: 13)))
        XCTAssertTrue(factory.shouldResetDecoder(for: makeFrame(sequenceNumber: 1)))
        XCTAssertTrue(factory.shouldResetDecoder(for: makeFrame(sequenceNumber: 12)))
    }

    func testDecoderResetsWhenH264ParameterSetsChange() {
        let factory = RemoteCameraMonitorSampleBufferFactory()
        factory.recordAcceptedFrame(
            makeFrame(sequenceNumber: 1, sps: Data([0x01, 0x02]), pps: Data([0x03]))
        )

        XCTAssertFalse(factory.shouldResetDecoder(for: makeFrame(
            sequenceNumber: 2,
            sps: Data([0x01, 0x02]),
            pps: Data([0x03])
        )))
        XCTAssertTrue(factory.shouldResetDecoder(for: makeFrame(
            sequenceNumber: 3,
            sps: Data([0x01, 0x04]),
            pps: Data([0x03])
        )))
        XCTAssertTrue(factory.shouldResetDecoder(for: makeFrame(
            sequenceNumber: 4,
            sps: Data([0x01, 0x02]),
            pps: Data([0x05])
        )))
    }

    private func makeFrame(
        sequenceNumber: Int64,
        sps: Data? = nil,
        pps: Data? = nil
    ) -> RemoteCameraMonitorVideoFrame {
        RemoteCameraMonitorVideoFrame(
            codec: .h264,
            data: Data([0x00, 0x00, 0x00, 0x01]),
            width: 1280,
            height: 720,
            presentationTimeSeconds: 0,
            frameDurationSeconds: 1.0 / 24.0,
            isKeyFrame: sps != nil && pps != nil,
            sequenceNumber: sequenceNumber,
            h264SPS: sps,
            h264PPS: pps
        )
    }
}

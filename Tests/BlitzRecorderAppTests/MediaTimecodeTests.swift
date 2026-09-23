import AppKit
import SwiftUI
import XCTest
@testable import BlitzRecorderApp

final class MediaTimecodeTests: XCTestCase {
    func testMinuteAndHourBoundariesKeepTheSameFormat() {
        XCTAssertEqual(MediaTimecode.label(.init(time: 50, duration: 500)), "00:50")
        XCTAssertEqual(MediaTimecode.label(.init(time: 61, duration: 500)), "01:01")
        XCTAssertEqual(MediaTimecode.label(.init(time: 3_000, duration: 5_400)), "0:50:00")
        XCTAssertEqual(MediaTimecode.label(.init(time: 3_660, duration: 5_400)), "1:01:00")
        XCTAssertEqual(MediaTimecode.label(.init(time: 3_600, duration: 36_000)), "01:00:00")
    }

    func testInvalidAndOutOfBoundsTimesStaySafe() {
        XCTAssertEqual(MediaTimecode.label(.init(time: .nan, duration: 5_400)), "0:00:00")
        XCTAssertEqual(MediaTimecode.label(.init(time: 6_000, duration: 5_400)), "1:30:00")
        XCTAssertEqual(MediaTimecode.label(.init(time: -5, duration: 5_400)), "0:00:00")
        XCTAssertEqual(MediaTimecode.label(.init(time: 1, duration: .infinity)), "00:00")
    }

    @MainActor
    func testTimecodeLayoutDoesNotMoveAtMinuteOrHourBoundaries() {
        for duration in [600.0, 5_400.0, 36_000.0] {
            let widths = [0.0, 50, 61, 599, 600, 3_000, 3_599, 3_660, duration].map { time in
                NSHostingView(rootView:
                    BlitzTimecode(configuration: .init(time: time, duration: duration))
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                ).fittingSize.width
            }
            XCTAssertGreaterThan(widths[0], 0)
            for width in widths { XCTAssertEqual(width, widths[0], accuracy: 0.01) }
        }
    }

    @MainActor
    func testEditorTransportWidthStaysFixedAcrossTheHour() {
        let widths = [3_000.0, 3_599, 3_660].map { time in
            NSHostingView(rootView: EditorPlaybackControls(configuration: .init(
                time: time, duration: 5_400, isPlaying: false, isEnabled: true, rate: .normal,
                onSeek: { _ in }, onTogglePlayback: {}, onRateChange: { _ in }
            ))).fittingSize.width
        }
        XCTAssertGreaterThan(widths[0], 0)
        for width in widths { XCTAssertEqual(width, widths[0], accuracy: 0.01) }
    }
}

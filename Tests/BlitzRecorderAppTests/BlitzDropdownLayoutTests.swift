import AppKit
import SwiftUI
import XCTest
@testable import BlitzRecorderApp

final class BlitzDropdownLayoutTests: XCTestCase {
    @MainActor
    func testCompactDropdownFitsEverySpeedWithoutChangingWidth() {
        let rates = EditorPlaybackRate.allCases
        let options = rates.map { BlitzDropdownOption(value: $0, title: $0.displayName, detail: nil) }
        var widths: [CGFloat] = []

        for rate in rates {
            let host = NSHostingView(rootView: BlitzDropdown(configuration: .init(
                title: "Playback speed",
                selection: .constant(rate),
                options: options,
                width: .content
            )))
            host.layoutSubtreeIfNeeded()
            let size = host.fittingSize
            let textWidth = (rate.displayName as NSString).size(withAttributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium)
            ]).width

            XCTAssertGreaterThan(size.width, textWidth + 32, "The value needs room beside the chevron and padding.")
            XCTAssertLessThanOrEqual(size.height, 36, "Short speed labels should stay on one line.")
            widths.append(size.width)
        }

        XCTAssertEqual(Set(widths).count, 1, "Changing the selected speed must not move adjacent controls.")
    }

    @MainActor
    func testLongSelectedValueWrapsWithinAConstrainedField() {
        let title = "External studio microphone"
        let host = NSHostingView(rootView: BlitzDropdown(configuration: .init(
            title: "Input",
            selection: .constant(title),
            options: [.init(value: title, title: title, detail: nil)]
        )).frame(width: 140))
        host.layoutSubtreeIfNeeded()

        XCTAssertEqual(host.fittingSize.width, 140, accuracy: 1)
        XCTAssertGreaterThan(host.fittingSize.height, 34, "A longer value must get a second line instead of collapsing.")
    }

    @MainActor
    func testVeryLongContentDoesNotExpandAcrossTheWindow() {
        let title = String(repeating: "Long recording device name ", count: 10)
        let host = NSHostingView(rootView: BlitzDropdown(configuration: .init(
            title: "Input",
            selection: .constant(title),
            options: [.init(value: title, title: title, detail: nil)],
            width: .content
        )))
        host.layoutSubtreeIfNeeded()

        XCTAssertLessThanOrEqual(host.fittingSize.width, 280)
        XCTAssertGreaterThan(host.fittingSize.height, 34)
    }
}

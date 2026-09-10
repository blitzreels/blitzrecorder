import AppKit
import SwiftUI
import XCTest
@testable import BlitzRecorderApp

final class BlitzIllustratedLabelTests: XCTestCase {
    @MainActor
    func testIllustratedSwitchWrapsWithoutStretchingANarrowInspector() {
        let titles = ["Smooth movement", "Camera follows zoom", "A much longer setting name that must remain readable"]
        for width: CGFloat in [260, 320, 400] {
            for title in titles {
                let host = NSHostingView(rootView:
                    Toggle(isOn: .constant(true)) {
                        BlitzIllustratedLabel(configuration: .init(
                            title: title,
                            detail: "A short explanation of the effect.",
                            preview: { _ in Color.gray }
                        ))
                    }
                    .toggleStyle(.blitzSwitch)
                    .frame(width: width)
                )
                host.layoutSubtreeIfNeeded()
                XCTAssertEqual(host.fittingSize.width, width, accuracy: 1)
                XCTAssertGreaterThanOrEqual(host.fittingSize.height, 58)
                XCTAssertLessThan(host.fittingSize.height, 180)
            }
        }
    }

    @MainActor
    func testEveryEffectRendersAStillWhenSourceFramesAreMissing() {
        let effects: [EditorMotionEffect] = [
            .smoothing(false), .smoothing(true), .clicks(false), .clicks(true),
            .cursorSize(0.75), .cursorSize(3), .zoom(amount: 1.3, enabled: true), .zoom(amount: 2.5, enabled: true),
            .zoom(amount: 2.5, enabled: false),
            .cameraFollow(false), .cameraFollow(true)
        ]
        for effect in effects {
            let renderer = ImageRenderer(content:
                EditorMotionPreview(configuration: .init(
                    effect: effect,
                    source: .init(screen: nil, camera: nil, background: .black),
                    isAnimating: false
                ))
                .frame(width: 80, height: 50)
            )
            let image = renderer.cgImage
            XCTAssertNotNil(image)
            XCTAssertEqual(image?.width, 80)
            XCTAssertEqual(image?.height, 50)
        }
    }
}

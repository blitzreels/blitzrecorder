import AppKit
import XCTest
@testable import BlitzRecorderApp

@MainActor
final class PreviewStageHitTestingTests: XCTestCase {
    func testCanvasRoutesClicksToVisibleSourcesInOffsetAndFlippedContainers() throws {
        for flipped in [false, true] {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1300, height: 1000),
                styleMask: [.borderless], backing: .buffered, defer: false)
            let parent = CanvasTestContainer(frame: CGRect(x: 0, y: 0, width: 1300, height: 1000))
            parent.usesFlippedCoordinates = flipped
            window.contentView = parent
            let stage = PreviewStageView()
            parent.addSubview(stage)
            stage.enabledSources = [.screen, .camera]
            stage.screenContentMode = .fit
            stage.sceneLayout = SceneLayout.screenSplitLayout(screenHeight: 0.42)
            for frame in [CGRect(x: 320, y: 114, width: 600, height: 740),
                          CGRect(x: 180, y: 72, width: 900, height: 620)] {
                stage.frame = frame
                for ratio in CaptureLayout.allCases {
                    stage.captureLayout = ratio
                    stage.layoutSubtreeIfNeeded()
                    let scene = stage.sceneLayout
                    for source in [SceneLayerKind.screen, .camera] {
                        stage.selectedLayer = source == .screen ? .camera : .screen
                        let sourceFrame = stage.frame(for: source)
                        for fraction: CGFloat in [0.15, 0.5, 0.85] {
                            let point = CGPoint(x: sourceFrame.minX + sourceFrame.width * fraction,
                                y: sourceFrame.minY + sourceFrame.height * fraction)
                            let parentPoint = stage.convert(point, to: parent)
                            let target = parent.hitTest(parent.convert(parentPoint, to: parent.superview))
                            XCTAssertTrue(target === stage, "\(ratio), flipped=\(flipped), \(source), \(point)")
                            guard target === stage else { continue }
                            let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
                                location: stage.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                                windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                clickCount: 1, pressure: 1))
                            target?.mouseDown(with: event)
                            XCTAssertEqual(stage.selectedLayer, source)
                            target?.mouseUp(with: event)
                            XCTAssertEqual(stage.sceneLayout, scene)
                        }
                    }
                }
            }
        }
    }

    func testCanvasDoesNotInterceptOutsideOrHiddenAreas() {
        let parent = NSView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        let stage = PreviewStageView()
        stage.frame = CGRect(x: 300, y: 180, width: 500, height: 400)
        parent.addSubview(stage)
        XCTAssertFalse(parent.hitTest(CGPoint(x: 80, y: 80)) === stage)
        XCTAssertTrue(parent.hitTest(CGPoint(x: 780, y: 560)) === stage)
        stage.isHidden = true
        XCTAssertFalse(parent.hitTest(CGPoint(x: 450, y: 320)) === stage)
    }
}

@MainActor
private final class CanvasTestContainer: NSView {
    var usesFlippedCoordinates = false
    override var isFlipped: Bool { usesFlippedCoordinates }
}

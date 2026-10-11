import AppKit
import CoreText
import XCTest
@testable import BlitzRecorderApp

final class EditorTextCanvasTests: XCTestCase {
    func testLongTextFitsEveryCharacterInsideSmallLandscapeAndPortraitBoxes() {
        for bounds in [CGSize(width: 220, height: 42), CGSize(width: 120, height: 180), CGSize(width: 500, height: 50)] {
            let text = String(repeating: "BlitzRecorder and BlitzReels — des sous-titres sans troncature. ", count: 12)
            let layout = FittedTextLayout.resolve(.init(text: text, fontSize: 64, weight: .bold,
                color: .white, alignment: .center, bounds: bounds))
            let setter = CTFramesetterCreateWithAttributedString(layout.text)
            let frame = CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: CGRect(origin: .zero, size: layout.size), transform: nil), nil)
            XCTAssertEqual(CTFrameGetVisibleStringRange(frame).length, (text as NSString).length)
            XCTAssertLessThanOrEqual(layout.size.height, bounds.height)
        }
    }

    func testDragUsesFreeCanvasCoordinatesAndResizeKeepsOppositeEdgeFixed() {
        let original = CGRect(x: 0.1, y: 0.7, width: 0.5, height: 0.15)
        let moved = EditorTextFrameEditing.frame(.init(frame: original, translation: .init(width: 0.2, height: -0.4), handle: nil))
        XCTAssertEqual(moved.minX, 0.3, accuracy: 0.001)
        XCTAssertEqual(moved.minY, 0.3, accuracy: 0.001)
        XCTAssertEqual(moved.size, original.size)
        let resized = EditorTextFrameEditing.frame(.init(frame: original,
            translation: .init(width: -0.08, height: -0.1), handle: .topLeft))
        XCTAssertEqual(resized.maxX, original.maxX, accuracy: 0.001)
        XCTAssertEqual(resized.maxY, original.maxY, accuracy: 0.001)
        XCTAssertEqual(resized.width, 0.58, accuracy: 0.001)
        let clamped = EditorTextFrameEditing.frame(.init(frame: original, translation: .init(width: 10, height: -10), handle: nil))
        XCTAssertEqual(clamped.maxX, 1, accuracy: 0.001)
        XCTAssertEqual(clamped.minY, 0, accuracy: 0.001)
    }

    func testCaptionPositionAndTimingSurviveSaveAndUseTheCustomCanvasBox() throws {
        var edits = TimelineEdits.empty
        edits.captions.isEnabled = true
        edits.captions.frame = CGRect(x: 0.1, y: 0.2, width: 0.45, height: 0.18)
        let id = UUID()
        edits.captions.cues = [.init(id: id, start: 1, end: 3, text: "Move this caption anywhere", words: [])]
        let item = try XCTUnwrap(EditorPlacedTrack.resolve(edits).first?.items.first)
        XCTAssertEqual(item.id.kind, .caption)
        let changed = try XCTUnwrap(EditorPlacedItemEditing.changing(.init(edits: edits,
            change: .init(id: item.id, timing: .init(start: 4, end: 8), gesture: .move))))
        let restored = try JSONDecoder().decode(RecordingProject.TimelineEditsSnapshot.self,
            from: JSONEncoder().encode(RecordingProject.TimelineEditsSnapshot(changed))).edits
        XCTAssertNil(CaptionTimeline(.init(track: restored.captions, cuts: [])).cue(at: 2))
        XCTAssertEqual(CaptionTimeline(.init(track: restored.captions, cuts: [])).cue(at: 6)?.text, edits.captions.cues[0].text)
        XCTAssertEqual(restored.captions.frame, edits.captions.frame)
        let sprite = try XCTUnwrap(CaptionRenderer.sprite(.init(.init(cue: restored.captions.cues[0],
            track: restored.captions, canvasSize: CGSize(width: 1920, height: 1080)))))
        XCTAssertEqual(sprite.frame.minX, 192, accuracy: 1)
        XCTAssertEqual(sprite.frame.minY, 216, accuracy: 1)
        XCTAssertEqual(sprite.frame.width, 864, accuracy: 1)
        XCTAssertEqual(sprite.frame.height, 194, accuracy: 1)
    }
}

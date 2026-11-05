import CoreImage
import XCTest
@testable import BlitzRecorderApp

final class CameraColorLookTests: XCTestCase {
    private func cube(_ id: String) throws -> CameraColorLUT {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try CubeLUTFile.load(url: root.appendingPathComponent("Resources/ColorLooks/\(id).cube"))
    }

    func testEveryLookHasAReadableCube() throws {
        for look in CameraColorLook.all {
            XCTAssertEqual(try cube(look.id).dimension, 33, look.id)
        }
    }

    func testLookPersistsForOnlyItsCameraRole() throws {
        var warm = CameraColorGrade.neutral
        warm.warmth = 0.35
        var mono = CameraColorGrade.neutral
        mono.lut = try cube("mono")
        mono.lut?.lookID = "mono"
        var edits = TimelineEdits.empty
        edits.cameraGrades["camera"] = warm
        edits.cameraGrades["camera-2"] = mono
        let restored = try JSONDecoder().decode(RecordingProject.TimelineEditsSnapshot.self,
            from: JSONEncoder().encode(RecordingProject.TimelineEditsSnapshot(edits))).edits
        XCTAssertEqual(restored.cameraGrades, edits.cameraGrades)
        XCTAssertEqual(restored.cameraGrades["camera-2"]?.lut?.lookID, "mono")
    }

    func testMonoRendersGrayAndNeutralPreservesOriginal() throws {
        let source = CIImage(color: CIColor(red: 0.7, green: 0.3, blue: 0.1))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        let original = pixel(source)
        var grade = CameraColorGrade.neutral
        grade.lut = try cube("mono")
        let mono = pixel(grade.applied(to: source))
        XCTAssertEqual(Double(mono[0]), Double(mono[1]), accuracy: 2)
        XCTAssertEqual(Double(mono[1]), Double(mono[2]), accuracy: 2)
        XCTAssertNotEqual(original, mono)
        XCTAssertEqual(pixel(CameraColorGrade.neutral.applied(to: source)), original)
    }

    private func pixel(_ image: CIImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        CIContext().render(image, toBitmap: &bytes, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB())
        return bytes
    }
}

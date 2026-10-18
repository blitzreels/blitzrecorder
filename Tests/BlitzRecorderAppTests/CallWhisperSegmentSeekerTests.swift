import CoreML
import XCTest
@testable import BlitzRecorderApp

final class CallWhisperSegmentSeekerTests: XCTestCase {
    func testShortReplyAlignmentExcludesPaddedSilenceAndRetainsSpeechWeights() throws {
        let weights = try MLMultiArray(shape: [3, 1500], dataType: .float32)
        for row in 0..<3 {
            for column in 0..<1500 { weights[row * 1500 + column] = NSNumber(value: row * 1500 + column) }
        }
        let result = try CallWhisperSegmentSeeker.speechAlignment(.init(weights: weights, sampleCount: 76_928, promptRows: 0))
        XCTAssertEqual(result.shape.map(\.intValue), [3, 241])
        XCTAssertEqual(result[240].intValue, 240)
        XCTAssertEqual(result[241].intValue, 1500)
        XCTAssertEqual(result[722].intValue, 3240)
    }

    func testFullWhisperWindowRetainsAlignment() throws {
        let weights = try MLMultiArray(shape: [2, 1500], dataType: .float16)
        let result = try CallWhisperSegmentSeeker.speechAlignment(.init(weights: weights, sampleCount: 480_000, promptRows: 0))
        XCTAssertTrue(result === weights)
    }

    func testVocabularyHintRowsDoNotShiftSpeechAlignment() throws {
        let weights = try MLMultiArray(shape: [8, 1500], dataType: .float16)
        for row in 0..<8 {
            for column in 0..<1500 { weights[row * 1500 + column] = NSNumber(value: row) }
        }
        let result = try CallWhisperSegmentSeeker.speechAlignment(.init(weights: weights, sampleCount: 80_000, promptRows: 3))
        XCTAssertEqual(result.shape.map(\.intValue), [5, 250])
        XCTAssertEqual(result[0].intValue, 3)
        XCTAssertEqual(result[1249].intValue, 7)
    }
}

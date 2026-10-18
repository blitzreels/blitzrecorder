import CoreML
import Foundation
import WhisperKit

struct CallWhisperSegmentSeeker: SegmentSeeking {
    private let base = SegmentSeeker()

    func findSeekPointAndSegments(
        decodingResult: DecodingResult, options: DecodingOptions, allSegmentsCount: Int,
        currentSeek: Int, segmentSize: Int, sampleRate: Int, timeToken: Int,
        specialToken: Int, tokenizer: WhisperTokenizer
    ) -> (Int, [TranscriptionSegment]?) {
        base.findSeekPointAndSegments(
            decodingResult: decodingResult, options: options, allSegmentsCount: allSegmentsCount,
            currentSeek: currentSeek, segmentSize: segmentSize, sampleRate: sampleRate,
            timeToken: timeToken, specialToken: specialToken, tokenizer: tokenizer
        )
    }

    func addWordTimestamps(
        segments: [TranscriptionSegment], alignmentWeights: MLMultiArray, tokenizer: WhisperTokenizer,
        seek: Int, segmentSize: Int, prependPunctuations: String, appendPunctuations: String,
        lastSpeechTimestamp: Float, options: DecodingOptions, timings: TranscriptionTimings
    ) throws -> [TranscriptionSegment]? {
        let promptRows = options.usePrefillPrompt ? options.promptTokens.map {
            $0.suffix((Constants.maxTokenContext / 2) - 1)
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }.count + 1
        } ?? 0 : 0
        return try base.addWordTimestamps(
            segments: segments,
            alignmentWeights: Self.speechAlignment(.init(weights: alignmentWeights, sampleCount: segmentSize,
                                                        promptRows: promptRows)),
            tokenizer: tokenizer, seek: seek, segmentSize: segmentSize,
            prependPunctuations: prependPunctuations, appendPunctuations: appendPunctuations,
            lastSpeechTimestamp: lastSpeechTimestamp, options: options, timings: timings
        )
    }

    struct AlignmentRequest {
        let weights: MLMultiArray
        let sampleCount: Int
        let promptRows: Int
    }

    static func speechAlignment(_ request: AlignmentRequest) throws -> MLMultiArray {
        let weights = request.weights
        guard weights.shape.count == 2 else { throw WhisperError.segmentingFailed("Invalid speech alignment") }
        let rows = weights.shape[0].intValue - request.promptRows
        guard request.promptRows >= 0, rows > 0 else { throw WhisperError.segmentingFailed("Invalid prompt alignment") }
        let columns = weights.shape[1].intValue
        let frames = min(columns, max(1, Int(ceil(Double(request.sampleCount) / 320))))
        guard frames < columns || request.promptRows > 0 else { return weights }
        let result = try MLMultiArray(shape: [NSNumber(value: rows), NSNumber(value: frames)], dataType: weights.dataType)
        let bytes: Int
        switch weights.dataType {
        case .float16: bytes = 2
        case .float32, .int32: bytes = 4
        case .double: bytes = 8
        default: throw WhisperError.segmentingFailed("Unsupported speech alignment")
        }
        if weights.strides[1].intValue == 1 {
            for row in 0..<rows {
                memcpy(result.dataPointer.advanced(by: row * result.strides[0].intValue * bytes),
                       weights.dataPointer.advanced(by: (row + request.promptRows) * weights.strides[0].intValue * bytes), frames * bytes)
            }
        } else {
            for row in 0..<rows {
                for column in 0..<frames {
                    result[[NSNumber(value: row), NSNumber(value: column)]] = weights[[NSNumber(value: row + request.promptRows), NSNumber(value: column)]]
                }
            }
        }
        return result
    }
}

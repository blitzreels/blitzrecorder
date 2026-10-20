import CoreGraphics
import Foundation
import Vision

/// Reads text from a rendered view for layout tests. When the machine is busy, Vision's text model can fail to load
/// with "InvalidTransition … failed(deinit)"; that one error is retried, anything else is thrown.
enum RenderedText {
    struct Request {
        let image: CGImage
        let customWords: [String]
    }

    static func observations(_ request: Request) throws -> [VNRecognizedTextObservation] {
        var attempt = 0
        while true {
            attempt += 1
            let recognition = VNRecognizeTextRequest()
            recognition.recognitionLevel = .accurate
            recognition.recognitionLanguages = ["en-US"]
            recognition.customWords = request.customWords
            do {
                try VNImageRequestHandler(cgImage: request.image).perform([recognition])
                return recognition.results ?? []
            } catch where attempt < 3 && String(describing: error).contains("InvalidTransition") {
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
    }
}

import Foundation

/// Without headphones the microphone also hears the call, so the call is transcribed twice: once as the call and
/// once as you. Speech heard on the microphone whose words mostly repeat what the call said at the same moment is
/// that echo. Only runs of several words in a row that the call did not say are kept from it: what is left
/// between repeated words is misheard echo, not you. Your own replies do not repeat the call and are kept whole.
enum LiveEchoFilter {
    static let windowSeconds = 1.5
    static let echoShare = 0.5
    static let keptWords = 4

    struct Request {
        let microphone: [TranscriptWord]
        let call: [TranscriptWord]
    }

    static func filtered(_ request: Request) -> [TranscriptWord] {
        let counted = request.microphone.filter { key($0.text).count >= 3 }
        guard !counted.isEmpty, !request.call.isEmpty else { return request.microphone }
        let echoed = request.microphone.map { word in
            let wordKey = key(word.text)
            return wordKey.count >= 3 && request.call.contains {
                abs($0.startTime - word.startTime) <= windowSeconds && key($0.text) == wordKey
            }
        }
        let share = Double(zip(request.microphone, echoed).filter { key($0.0.text).count >= 3 && $0.1 }.count)
            / Double(counted.count)
        guard share >= echoShare else { return request.microphone }
        var kept: [TranscriptWord] = []
        var run: [TranscriptWord] = []
        for (word, isEcho) in zip(request.microphone, echoed) {
            if isEcho {
                if run.count >= keptWords { kept += run }
                run = []
            } else {
                run.append(word)
            }
        }
        if run.count >= keptWords { kept += run }
        return kept
    }

    static func key(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }
}

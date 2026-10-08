import Foundation

enum TranscriptionVocabulary {
    static let defaultsKey = "transcription.vocabulary"

    static func prompt(_ names: [String]) -> String {
        terms(.init(custom: UserDefaults.standard.string(forKey: defaultsKey) ?? "", names: names))
            .joined(separator: ", ")
    }

    struct Request {
        let custom: String
        let names: [String]
    }

    static func terms(_ request: Request) -> [String] {
        var seen = Set<String>()
        return (request.custom.components(separatedBy: CharacterSet(charactersIn: ",\n")) + request.names)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 80 && seen.insert($0.lowercased()).inserted }
            .prefix(40).map { $0 }
    }
}

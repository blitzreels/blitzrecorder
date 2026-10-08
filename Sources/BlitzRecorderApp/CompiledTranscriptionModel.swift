import Foundation

enum CompiledTranscriptionModel {
    static func validate(_ directory: URL) throws {
        try requireFile(directory.appendingPathComponent("coremldata.bin"))
        let programURL = directory.appendingPathComponent("model.mil")
        guard FileManager.default.fileExists(atPath: programURL.path) else { return }
        let program = try String(contentsOf: programURL, encoding: .utf8)
        let expression = try NSRegularExpression(pattern: #"@model_path/([^"\n]+)"#)
        let matches = expression.matches(in: program, range: NSRange(program.startIndex..., in: program))
        let paths = Set(matches.compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: program) else { return nil }
            return String(program[range])
        })
        for path in paths.sorted() {
            try requireFile(directory.appendingPathComponent(path))
        }
    }

    private static func requireFile(_ url: URL) throws {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, let size = values.fileSize, size > 0,
              FileManager.default.isReadableFile(atPath: url.path) else {
            throw LocalTranscriptionError.incompleteModel(url.lastPathComponent)
        }
    }
}

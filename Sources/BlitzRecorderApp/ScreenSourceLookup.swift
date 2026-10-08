import Foundation

enum ScreenSourceLookup {
    static func resolve<Source>(_ load: () async throws -> Source) async throws -> Source {
        for attempt in 0...2 {
            try Task.checkCancellation()
            do {
                return try await load()
            } catch RecorderError.screenSourceUnavailable where attempt < 2 {
                try await Task.sleep(for: .milliseconds(200))
            }
        }
        throw CancellationError()
    }
}

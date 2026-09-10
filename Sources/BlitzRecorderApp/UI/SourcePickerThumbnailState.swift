import AppKit
import Observation

struct SourcePickerThumbnailID: Equatable, Hashable {
    let sourceID: String
    let revision: Int
}

@MainActor
@Observable
final class SourcePickerThumbnailState {
    struct Request {
        let id: SourcePickerThumbnailID
        let load: (() async -> NSImage?)?
    }

    private(set) var id: SourcePickerThumbnailID?
    private(set) var image: NSImage?
    private(set) var isLoading = false
    private var generation = 0

    func load(_ request: Request) async {
        generation += 1
        let currentGeneration = generation
        id = request.id
        image = nil
        isLoading = request.load != nil
        guard let load = request.load else { return }
        let result = await load()
        guard generation == currentGeneration else { return }
        isLoading = false
        guard !Task.isCancelled else { return }
        image = result
    }
}

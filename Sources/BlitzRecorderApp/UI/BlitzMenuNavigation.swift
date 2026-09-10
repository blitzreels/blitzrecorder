import Foundation

enum BlitzMenuNavigation {
    struct Move {
        let entries: [BlitzMenuEntry]
        let currentIndex: Int?
        let offset: Int
    }

    static func enabledIndices(_ entries: [BlitzMenuEntry]) -> [Int] {
        entries.indices.filter {
            if case .item(let item) = entries[$0] { return item.isEnabled }
            return false
        }
    }

    static func initialIndex(_ entries: [BlitzMenuEntry]) -> Int? {
        let indices = enabledIndices(entries)
        return indices.first {
            if case .item(let item) = entries[$0] { return item.isSelected }
            return false
        } ?? indices.first
    }

    static func movedIndex(_ request: Move) -> Int? {
        let indices = enabledIndices(request.entries)
        guard !indices.isEmpty else { return nil }
        guard let current = request.currentIndex.flatMap({ indices.firstIndex(of: $0) }) else {
            return request.offset < 0 ? indices.last : indices.first
        }
        return indices[min(indices.count - 1, max(0, current + request.offset))]
    }
}

import Foundation
import Observation

struct ProjectFolderPath: Hashable {
    static let separator = " - "

    let segments: [String]

    init?(_ segments: [String]) {
        let trimmed = segments.map { $0.trimmingCharacters(in: .whitespaces) }
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isEmpty) else { return nil }
        self.segments = trimmed
    }

    var name: String { segments[segments.count - 1] }
    var title: String { segments.joined(separator: Self.separator) }
    var displayPath: String { segments.joined(separator: " › ") }
    var id: String { segments.map { $0.lowercased() }.joined(separator: "/") }
    var parent: ProjectFolderPath? { ProjectFolderPath(Array(segments.dropLast())) }
    var ancestorsAndSelf: [ProjectFolderPath] {
        (1...segments.count).compactMap { ProjectFolderPath(Array(segments.prefix($0))) }
    }

    func appending(_ name: String) -> ProjectFolderPath? { ProjectFolderPath(segments + [name]) }

    func hasPrefix(_ other: ProjectFolderPath) -> Bool {
        segments.count >= other.segments.count
            && ProjectFolderPath(Array(segments.prefix(other.segments.count))) == other
    }

    struct PrefixReplacement {
        let from: ProjectFolderPath
        let to: ProjectFolderPath
    }

    func replacingPrefix(_ request: PrefixReplacement) -> ProjectFolderPath {
        guard hasPrefix(request.from) else { return self }
        return ProjectFolderPath(request.to.segments + segments.dropFirst(request.from.segments.count)) ?? self
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static func isValidName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains(separator) && !trimmed.contains("/") && !trimmed.contains(":")
            && ProjectLessonCode(trimmed) == nil
    }
}

struct ProjectLessonCode: Equatable {
    let module: Int
    let lesson: Int

    init(module: Int, lesson: Int) {
        self.module = module
        self.lesson = lesson
    }

    init?(_ segment: String) {
        let pattern = #"^[SM]([0-9]+)[EL]([0-9]+)$"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = expression.firstMatch(in: segment, range: NSRange(segment.startIndex..., in: segment)),
              let moduleRange = Range(match.range(at: 1), in: segment),
              let lessonRange = Range(match.range(at: 2), in: segment),
              let module = Int(segment[moduleRange]), let lesson = Int(segment[lessonRange]) else { return nil }
        self.init(module: module, lesson: lesson)
    }

    var formatted: String { "M\(Self.number(module))L\(Self.number(lesson))" }

    static func number(_ value: Int) -> String { String(format: "%02d", value) }
}

struct ProjectFolderTitle: Equatable {
    static let untitled = "Untitled"

    let folder: ProjectFolderPath?
    let code: ProjectLessonCode?
    let title: String

    var formatted: String {
        ((folder?.segments ?? []) + [code?.formatted].compactMap { $0 } + [title]).joined(separator: ProjectFolderPath.separator)
    }

    func with(_ title: String) -> ProjectFolderTitle { .init(folder: folder, code: code, title: title) }

    static func segments(_ title: String) -> [String] {
        title.components(separatedBy: ProjectFolderPath.separator).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func coded(_ title: String) -> ProjectFolderTitle? {
        let parts = segments(title)
        guard parts.count >= 3 else { return nil }
        for index in 1..<(parts.count - 1) {
            guard let code = ProjectLessonCode(parts[index]) else { continue }
            guard let folder = ProjectFolderPath(Array(parts.prefix(index))) else { return nil }
            let rest = parts.dropFirst(index + 1).joined(separator: ProjectFolderPath.separator)
            return rest.isEmpty ? nil : .init(folder: folder, code: code, title: rest)
        }
        return nil
    }

    static func untitledPrefix(_ title: String) -> String? {
        if title == untitled { return "" }
        let suffix = ProjectFolderPath.separator + untitled
        return title.hasSuffix(suffix) ? String(title.dropLast(untitled.count)) : nil
    }

    static func baseTitle(_ title: String) -> String {
        RecordingProjectDisplayTitle.isUntitled(title) ? untitled : title
    }
}

struct ProjectFolderPin: Codable, Equatable {
    var path: [String]
    var modules: [Int]
    var numbered: Bool

    var folderPath: ProjectFolderPath? { ProjectFolderPath(path) }
}

struct ProjectFolderIndex {
    struct Request {
        let projects: [RecordingProjectHistory.Entry]
        let pins: [ProjectFolderPin]
    }

    let known: Set<ProjectFolderPath>
    let pins: [ProjectFolderPath: ProjectFolderPin]
    private let titles: [UUID: ProjectFolderTitle]

    init(_ request: Request) {
        var known = Set(request.pins.compactMap(\.folderPath).flatMap(\.ancestorsAndSelf))
        var counts: [ProjectFolderPath: Set<UUID>] = [:]
        for entry in request.projects {
            if let coded = ProjectFolderTitle.coded(entry.title), let folder = coded.folder {
                known.formUnion(folder.ancestorsAndSelf)
                continue
            }
            let parts = ProjectFolderTitle.segments(entry.title)
            guard parts.count > 1 else { continue }
            for length in 1..<parts.count {
                if let path = ProjectFolderPath(Array(parts.prefix(length))) { counts[path, default: []].insert(entry.id) }
            }
        }
        for (path, ids) in counts where ids.count > 1 { known.formUnion(path.ancestorsAndSelf) }
        self.known = known
        pins = Dictionary(request.pins.compactMap { pin in pin.folderPath.map { ($0, pin) } }, uniquingKeysWith: { lhs, _ in lhs })
        titles = Dictionary(request.projects.map { ($0.id, Self.parse(.init(title: $0.title, known: known))) },
                            uniquingKeysWith: { lhs, _ in lhs })
    }

    struct ParseRequest {
        let title: String
        let known: Set<ProjectFolderPath>
    }

    static func parse(_ request: ParseRequest) -> ProjectFolderTitle {
        if let coded = ProjectFolderTitle.coded(request.title) { return coded }
        let parts = ProjectFolderTitle.segments(request.title)
        if parts.count > 1 {
            for length in stride(from: parts.count - 1, through: 1, by: -1) {
                guard let path = ProjectFolderPath(Array(parts.prefix(length))), request.known.contains(path) else { continue }
                return .init(folder: path, code: nil, title: parts.dropFirst(length).joined(separator: ProjectFolderPath.separator))
            }
        }
        return .init(folder: nil, code: nil, title: request.title)
    }

    func resolved(_ entry: RecordingProjectHistory.Entry) -> ProjectFolderTitle {
        titles[entry.id] ?? Self.parse(.init(title: entry.title, known: known))
    }

    func isNumbered(_ path: ProjectFolderPath) -> Bool { pins[path]?.numbered == true }
}

@MainActor
@Observable
final class ProjectFolderStore {
    static let shared = ProjectFolderStore(defaults: .standard)
    private static let key = "projects.folders.v2"
    private static let legacyKey = "projects.courseFolders.v1"

    private struct LegacyFolder: Codable {
        let name: String
        let modules: [Int]
    }

    private let defaults: UserDefaults
    private(set) var pins: [ProjectFolderPin]

    init(defaults: UserDefaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key), let pins = try? JSONDecoder().decode([ProjectFolderPin].self, from: data) {
            self.pins = pins
        } else {
            pins = (defaults.data(forKey: Self.legacyKey)
                .flatMap { try? JSONDecoder().decode([LegacyFolder].self, from: $0) } ?? [])
                .map { .init(path: [$0.name], modules: $0.modules, numbered: true) }
        }
    }

    func pin(_ path: ProjectFolderPath) {
        guard !pins.contains(where: { $0.folderPath == path }) else { return }
        pins.append(.init(path: path.segments, modules: [], numbered: false))
        save()
    }

    struct ModuleRequest {
        let path: ProjectFolderPath
        let module: Int
    }

    func pinModule(_ request: ModuleRequest) {
        pin(request.path)
        guard let index = pins.firstIndex(where: { $0.folderPath == request.path }) else { return }
        pins[index].numbered = true
        if !pins[index].modules.contains(request.module) { pins[index].modules = (pins[index].modules + [request.module]).sorted() }
        save()
    }

    func rename(_ request: ProjectFolderPath.PrefixReplacement) {
        pins = pins.map { pin in
            guard let path = pin.folderPath else { return pin }
            return .init(path: path.replacingPrefix(request).segments, modules: pin.modules, numbered: pin.numbered)
        }
        var seen = Set<ProjectFolderPath>()
        pins = pins.filter { $0.folderPath.map { seen.insert($0).inserted } ?? false }
        save()
    }

    func remove(_ path: ProjectFolderPath) {
        pins.removeAll { $0.folderPath?.hasPrefix(path) ?? true }
        save()
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(pins), forKey: Self.key)
    }
}

enum ProjectFolderTree {
    struct Module: Identifiable {
        let id: Int
        let projects: [RecordingProjectHistory.Entry]
        let duplicateLessonIDs: Set<UUID>
    }

    struct Node: Identifiable {
        let path: ProjectFolderPath
        let children: [Node]
        let modules: [Module]
        let projects: [RecordingProjectHistory.Entry]
        let isNumbered: Bool

        var id: String { path.id }
        var allProjects: [RecordingProjectHistory.Entry] {
            modules.flatMap(\.projects) + projects + children.flatMap(\.allProjects)
        }
        var flattened: [Node] { [self] + children.flatMap(\.flattened) }
        var nextModule: Int { (modules.map(\.id).max() ?? 0) + 1 }
        var lastModule: Int { modules.last?.id ?? 1 }
    }

    struct Request {
        let projects: [RecordingProjectHistory.Entry]
        let index: ProjectFolderIndex
        let includesEmpty: Bool
    }

    static func roots(_ request: Request) -> [Node] {
        var byFolder: [ProjectFolderPath: [(RecordingProjectHistory.Entry, ProjectFolderTitle)]] = [:]
        var paths = Set<ProjectFolderPath>()
        for entry in request.projects {
            let resolved = request.index.resolved(entry)
            guard let folder = resolved.folder else { continue }
            byFolder[folder, default: []].append((entry, resolved))
            paths.formUnion(folder.ancestorsAndSelf)
        }
        if request.includesEmpty { paths.formUnion(request.index.pins.keys.flatMap(\.ancestorsAndSelf)) }
        let children = Dictionary(grouping: paths.filter { $0.segments.count > 1 }, by: { $0.parent?.id ?? "" })
        func build(_ path: ProjectFolderPath) -> Node {
            let members = byFolder[path] ?? []
            let coded = members.filter { $0.1.code != nil }
            var modules = Dictionary(grouping: coded, by: { $0.1.code?.module ?? 1 })
            if request.includesEmpty || members.isEmpty {
                for module in request.index.pins[path]?.modules ?? [] where modules[module] == nil { modules[module] = [] }
            }
            let builtModules = modules.map { module, lessons in
                let sorted = lessons.sorted {
                    let left = $0.1.code?.lesson ?? 0, right = $1.1.code?.lesson ?? 0
                    if left != right { return left < right }
                    if $0.0.recordedAt != $1.0.recordedAt { return $0.0.recordedAt < $1.0.recordedAt }
                    return $0.0.id.uuidString < $1.0.id.uuidString
                }
                let repeated = Set(Dictionary(grouping: sorted, by: { $0.1.code?.lesson ?? 0 }).values
                    .filter { $0.count > 1 }.flatMap { $0.map(\.0.id) })
                return Module(id: module, projects: sorted.map(\.0), duplicateLessonIDs: repeated)
            }.sorted { $0.id < $1.id }
            let plain = members.filter { $0.1.code == nil }.map(\.0).sorted { $0.recordedAt > $1.recordedAt }
            return Node(
                path: path,
                children: (children[path.id] ?? []).map(build).sorted(by: nameOrder),
                modules: builtModules, projects: plain,
                isNumbered: !builtModules.isEmpty || request.index.isNumbered(path)
            )
        }
        return paths.filter { $0.segments.count == 1 }.map(build).sorted(by: nameOrder)
    }

    private static func nameOrder(_ lhs: Node, _ rhs: Node) -> Bool {
        lhs.path.name.localizedStandardCompare(rhs.path.name) == .orderedAscending
    }
}

enum ProjectFolderMoves {
    enum Destination: Equatable {
        case folder(path: ProjectFolderPath, module: Int?, before: UUID?)
        case loose
    }

    struct Request {
        let moving: [RecordingProjectHistory.Entry]
        let destination: Destination
        let index: ProjectFolderIndex
        let library: [RecordingProjectHistory.Entry]
    }

    static func titles(_ request: Request) -> [UUID: String] {
        let base = { (entry: RecordingProjectHistory.Entry) in
            ProjectFolderTitle.baseTitle(request.index.resolved(entry).title)
        }
        switch request.destination {
        case .loose:
            return changed(request.moving.map { ($0, base($0)) })
        case .folder(let path, nil, _):
            return changed(request.moving.map { ($0, ProjectFolderTitle(folder: path, code: nil, title: base($0)).formatted) })
        case .folder(let path, let module?, let before):
            let movingIDs = Set(request.moving.map(\.id))
            let members = request.library.compactMap { entry -> (RecordingProjectHistory.Entry, Int)? in
                let resolved = request.index.resolved(entry)
                guard resolved.folder == path, let code = resolved.code, code.module == module else { return nil }
                return (entry, code.lesson)
            }.sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.recordedAt < $1.0.recordedAt }
            let memberIDs = Set(members.map(\.0.id))
            let lessonOf = Dictionary(members.map { ($0.0.id, $0.1) }, uniquingKeysWith: { lhs, _ in lhs })
            let incoming = request.moving.sorted { lhs, rhs in
                let left = lessonOf[lhs.id], right = lessonOf[rhs.id]
                if let left, let right, left != right { return left < right }
                if (left == nil) != (right == nil) { return left != nil }
                return lhs.recordedAt < rhs.recordedAt
            }
            let folder = members.first.flatMap { request.index.resolved($0.0).folder } ?? path
            func title(_ entry: RecordingProjectHistory.Entry, _ lesson: Int) -> String {
                ProjectFolderTitle(folder: folder, code: .init(module: module, lesson: lesson), title: base(entry)).formatted
            }
            if before == nil, memberIDs.isDisjoint(with: movingIDs) {
                let start = (members.map(\.1).max() ?? 0) + 1
                return changed(incoming.enumerated().map { ($1, title($1, start + $0)) })
            }
            var order = members.map(\.0).filter { !movingIDs.contains($0.id) }
            let insertion = before.flatMap { id in order.firstIndex { $0.id == id } } ?? order.count
            order.insert(contentsOf: incoming, at: insertion)
            return changed(order.enumerated().map { ($1, title($1, $0 + 1)) })
        }
    }

    struct RenameRequest {
        let replacement: ProjectFolderPath.PrefixReplacement
        let index: ProjectFolderIndex
        let library: [RecordingProjectHistory.Entry]
    }

    static func titles(_ request: RenameRequest) -> [UUID: String] {
        changed(request.library.compactMap { entry in
            let resolved = request.index.resolved(entry)
            guard let folder = resolved.folder, folder.hasPrefix(request.replacement.from) else { return nil }
            return (entry, ProjectFolderTitle(folder: folder.replacingPrefix(request.replacement), code: resolved.code,
                                              title: resolved.title).formatted)
        })
    }

    struct NextTitleRequest {
        let target: ProjectFolderRecordTarget
        let index: ProjectFolderIndex
        let library: [RecordingProjectHistory.Entry]
    }

    static func nextTitle(_ request: NextTitleRequest) -> ProjectFolderTitle {
        guard let module = request.target.module else {
            return .init(folder: request.target.path, code: nil, title: ProjectFolderTitle.untitled)
        }
        let lessons = request.library.compactMap { entry -> Int? in
            let resolved = request.index.resolved(entry)
            guard resolved.folder == request.target.path, resolved.code?.module == module else { return nil }
            return resolved.code?.lesson
        }
        return .init(folder: request.target.path, code: .init(module: module, lesson: (lessons.max() ?? 0) + 1),
                     title: ProjectFolderTitle.untitled)
    }

    private static func changed(_ pairs: [(RecordingProjectHistory.Entry, String)]) -> [UUID: String] {
        Dictionary(pairs.filter { $0.0.title != $0.1 }.map { ($0.0.id, $0.1) }, uniquingKeysWith: { lhs, _ in lhs })
    }
}

struct ProjectFolderRecordTarget: Hashable {
    let path: ProjectFolderPath
    let module: Int?
}

struct ProjectTitlePresentation: Equatable {
    struct Request {
        let title: String
        let known: Set<ProjectFolderPath>
    }

    let title: String
    let context: String?

    init(_ request: Request) {
        let resolved = ProjectFolderIndex.parse(.init(title: request.title, known: request.known))
        title = ProjectFolderTitle.baseTitle(resolved.title)
        let lesson = resolved.code.map {
            "Module \(ProjectLessonCode.number($0.module)) · Lesson \(ProjectLessonCode.number($0.lesson))"
        }
        let parts = [resolved.folder?.displayPath, lesson].compactMap { $0 }
        context = parts.isEmpty ? nil : parts.joined(separator: " › ")
    }
}

struct ProjectFolderScope: Hashable {
    let path: ProjectFolderPath
    let module: Int?

    var title: String {
        module.map { "\(path.displayPath) › Module \(ProjectLessonCode.number($0))" } ?? path.displayPath
    }

    func contains(_ resolved: ProjectFolderTitle) -> Bool {
        guard let folder = resolved.folder, folder.hasPrefix(path) else { return false }
        guard let module else { return true }
        return folder == path && resolved.code?.module == module
    }

    func replacingPrefix(_ request: ProjectFolderPath.PrefixReplacement) -> ProjectFolderScope {
        .init(path: path.replacingPrefix(request), module: module)
    }
}

import Foundation

public enum TakeFolderLayout: Sendable {
    public static let takeManifestName = "take.json"
    public static let projectName = "project.blitzrecorder.json"
    public static let screenName = "screen.mp4"
    public static let cameraName = "camera.mp4"
    public static let exportName = "export.mp4"
    public static let microphoneName = "audio.m4a"
    public static let systemAudioName = "system-audio.m4a"
    public static let cursorTrackName = "cursor-track.json"
    public static let transcriptName = "transcript.json"

    public static func takeDirectoryName(createdAt: Date = Date(), id: UUID = UUID()) -> String {
        let stamp = ISO8601DateFormatter.string(from: createdAt, timeZone: TimeZone.current)
            .replacingOccurrences(of: ":", with: "-")
        return "take-\(stamp)-\(id.uuidString.prefix(8))"
    }
}

private extension ISO8601DateFormatter {
    static func string(from date: Date, timeZone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }
}

public struct TakeManifest: Codable, Equatable, Sendable {
    public var id: UUID
    public var createdAt: Date

    public init(id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id
        self.createdAt = createdAt
    }
}

public struct PortableProject: Codable, Equatable, Sendable {
    public struct SourceFile: Codable, Equatable, Sendable {
        public var role: String
        public var path: String

        public init(role: String, path: String) {
            self.role = role
            self.path = path
        }
    }

    public var version: Int
    public var sources: [SourceFile]
    public var cuts: [TimelineCut]
    public var scene: PortableSceneLayout

    public init(
        version: Int = 1,
        sources: [SourceFile],
        cuts: [TimelineCut] = [],
        scene: PortableSceneLayout = .default
    ) {
        self.version = version
        self.sources = sources
        self.cuts = cuts
        self.scene = scene
    }

    public static func screenAndAudio(
        hasMicrophone: Bool,
        hasSystemAudio: Bool,
        hasCamera: Bool = false
    ) -> PortableProject {
        var sources = [SourceFile(role: "screen", path: TakeFolderLayout.screenName)]
        if hasCamera {
            sources.append(SourceFile(role: "camera", path: TakeFolderLayout.cameraName))
        }
        if hasMicrophone {
            sources.append(SourceFile(role: "microphone", path: TakeFolderLayout.microphoneName))
        }
        if hasSystemAudio {
            sources.append(SourceFile(role: "systemAudio", path: TakeFolderLayout.systemAudioName))
        }
        return PortableProject(
            sources: sources,
            scene: hasCamera ? .screenWithCameraPip : .screenOnly
        )
    }

    public var hasCamera: Bool {
        sources.contains { $0.role == "camera" }
    }

    enum CodingKeys: String, CodingKey {
        case version, sources, cuts, scene
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        sources = try container.decode([SourceFile].self, forKey: .sources)
        cuts = try container.decodeIfPresent([TimelineCut].self, forKey: .cuts) ?? []
        scene = try container.decodeIfPresent(PortableSceneLayout.self, forKey: .scene) ?? .default
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(sources, forKey: .sources)
        try container.encode(cuts, forKey: .cuts)
        try container.encode(scene, forKey: .scene)
    }
}

public enum TakeJSON {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    public static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try encode(value).write(to: url, options: .atomic)
    }

    public static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(contentsOf: url))
    }
}

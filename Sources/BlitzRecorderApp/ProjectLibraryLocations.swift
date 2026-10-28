import Foundation

/// Where the library's recordings live, disk by disk: each library folder with its disk, whether that disk is
/// connected and how many recordings it holds, plus libraries found on connected disks that the app does not read
/// yet. The Recordings banner and the Libraries settings read this one value, so a recording on an unplugged disk
/// is reported as offline instead of silently missing.
struct ProjectLibraryLocations: Equatable {
    struct Location: Equatable, Identifiable {
        let url: URL
        /// The disk's name, such as "harddrive" or "Macintosh HD".
        let diskName: String
        let isExternal: Bool
        /// New recordings are saved here.
        let isRecordingDestination: Bool
        let isConnected: Bool
        /// Nil while the disk is not connected.
        let recordingCount: Int?

        var id: String { url.path }
    }

    struct Suggestion: Equatable, Identifiable {
        let url: URL
        let diskName: String
        let recordingCount: Int

        var id: String { url.path }
    }

    struct ScanRequest {
        let libraries: [RecordingStorageLocation]
        let destination: RecordingStorageLocation
        /// Mounted disks and other folders that may hold a library, such as each volume and the Movies folder.
        let searchRoots: [URL]
    }

    let locations: [Location]
    let suggestions: [Suggestion]

    static let empty = ProjectLibraryLocations(locations: [], suggestions: [])

    var offline: [Location] { locations.filter { !$0.isConnected } }

    static func scan(_ request: ScanRequest) -> ProjectLibraryLocations {
        let destination = canonical(request.destination.url)
        let locations = request.libraries.map { library -> Location in
            let url = canonical(library.url)
            let isConnected = isDirectory(url)
            return Location(
                url: url, diskName: diskName(of: url), isExternal: isExternal(url),
                isRecordingDestination: url == destination, isConnected: isConnected,
                recordingCount: isConnected ? recordingCount(in: url) : nil
            )
        }
        let known = Set(locations.map(\.url))
        var seen = known
        var suggestions: [Suggestion] = []
        for root in request.searchRoots {
            for candidate in [root] + subfolders(of: canonical(root)) where !seen.contains(candidate) {
                guard let count = recordingCount(in: candidate), count > 0 else { continue }
                seen.insert(candidate)
                suggestions.append(Suggestion(url: candidate, diskName: diskName(of: candidate), recordingCount: count))
            }
        }
        return ProjectLibraryLocations(locations: locations, suggestions: suggestions)
    }

    /// Every mounted disk except the startup disk, and the default library folder in Movies.
    static var defaultSearchRoots: [URL] {
        let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeIsRootFileSystemKey], options: [.skipHiddenVolumes]
        ) ?? []
        let external = volumes.filter {
            (try? $0.resourceValues(forKeys: [.volumeIsRootFileSystemKey]).volumeIsRootFileSystem) != true
        }
        let movies = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies", isDirectory: true)
            .appendingPathComponent("BlitzRecorder", isDirectory: true)
        return external + [movies]
    }

    /// The recordings a library folder holds: its index's entries whose project file is still there, or its take
    /// folders when the index is missing. Nil when the folder holds no BlitzRecorder library.
    static func recordingCount(in folder: URL) -> Int? {
        let index = folder.appendingPathComponent("BlitzRecorder Projects", isDirectory: true)
            .appendingPathComponent("projects.json")
        if let data = try? Data(contentsOf: index),
           let history = try? JSONDecoder().decode(IndexCount.self, from: data) {
            return history.entries.filter { entry in
                entry.projectPath.map { FileManager.default.fileExists(atPath: $0) } ?? true
            }.count
        }
        let takes = folder.appendingPathComponent("BlitzRecorder Source Takes", isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: takes.path) else { return nil }
        return names.filter { !$0.hasPrefix(".") }.count
    }

    private struct IndexCount: Decodable {
        struct Entry: Decodable {
            let projectPath: String?
        }
        let entries: [Entry]
    }

    private static func subfolders(of root: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey]
        let children = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        )) ?? []
        return children.filter { (try? $0.resourceValues(forKeys: Set(keys)).isDirectory) == true }.map(canonical)
    }

    private static func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }

    /// The disk a folder is on. A folder on a disk that is not mounted is named after its /Volumes component.
    private static func diskName(of url: URL) -> String {
        let components = url.pathComponents
        if components.count > 2, components[1] == "Volumes" { return components[2] }
        return (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? "This Mac"
    }

    private static func isExternal(_ url: URL) -> Bool {
        let components = url.pathComponents
        return components.count > 2 && components[1] == "Volumes"
    }
}

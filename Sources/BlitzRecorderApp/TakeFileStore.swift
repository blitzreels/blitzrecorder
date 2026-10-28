import CoreGraphics
import CoreMedia
import Foundation
import os

private let libraryLog = Logger(subsystem: "dev.blitzreels.blitzrecorder", category: "library")

/// The project changed on disk after the editor loaded it; `current` is what is saved now.
struct ProjectEditConflict: LocalizedError {
    let current: RecordingProject

    var errorDescription: String? {
        "This recording changed somewhere else, so your change was not saved. The latest version is loaded; make the change again."
    }
}

/// Posted after a save changes a project's edits, so editors holding an older copy can load the new one.
/// Renames and finished exports post it with an unchanged revision: same edits, newer title or export list.
struct RecordingProjectEdited: Sendable {
    let projectPath: String
    let editRevision: Int
}

extension Notification.Name {
    static let recordingProjectEdited = Notification.Name("dev.blitzreels.blitzrecorder.project-edited")
}

struct TakeFileStore {
    private static let projectHistoryLock = NSRecursiveLock()
    /// Serializes every read-modify-write of a project file in this process.
    static let projectWriteLock = NSRecursiveLock()
    static let projectCache = ProjectFileCache()

    /// The in-memory copy an editor change is worked out on. While it is set, reading or writing its project
    /// uses the copy instead of the file, so the editor's existing edit functions run without touching disk.
    final class ProjectDraft: @unchecked Sendable {
        let projectPath: String
        var project: RecordingProject

        init(projectURL: URL, project: RecordingProject) {
            projectPath = ProjectSaveQueue.key(for: projectURL)
            self.project = project
        }

        func matches(_ url: URL) -> Bool { ProjectSaveQueue.key(for: url) == projectPath }

        /// Runs an editor change on this copy and returns the project it makes. Nothing is written.
        func stage(_ change: () throws -> RecordingProject) throws -> RecordingProject {
            try TakeFileStore.$draft.withValue(self) { _ = try change() }
            return project
        }
    }

    @TaskLocal static var draft: ProjectDraft?

    static func logLibraryIndexFailure(_ error: Error) {
        libraryLog.error("Could not update the library index: \(error.localizedDescription, privacy: .public)")
    }

    func loadProjectHistory(settings: RecordingSettings) -> RecordingProjectHistory {
        var entries: [RecordingProjectHistory.Entry] = []
        let roots = Set(settings.projectLibraries.map { $0.url.standardizedFileURL.resolvingSymlinksInPath() })
        for location in settings.projectLibraries {
            var librarySettings = settings
            librarySettings.projectLibrary = location
            let access = OutputDirectoryAccess(locations: [location])
            defer { access.stop() }
            guard access.hasSecurityScopedAccess else { continue }
            let root = location.url.standardizedFileURL.resolvingSymlinksInPath()
            let rootIsTemporary = Self.isTemporary(root.path)
            let local = (try? loadLocalProjectHistory(settings: librarySettings)) ?? rebuiltProjectHistory(settings: librarySettings)
            entries += local.entries.filter {
                let owner = URL(fileURLWithPath: $0.takeDirectoryPath).deletingLastPathComponent().deletingLastPathComponent()
                    .standardizedFileURL.resolvingSymlinksInPath()
                return (owner == root || !roots.contains(owner)) && (rootIsTemporary || !Self.isTemporary($0.takeDirectoryPath))
            }
        }
        entries.sort { $0.updatedAt > $1.updatedAt }
        var ids: Set<UUID> = []
        var paths: Set<String> = []
        var history = RecordingProjectHistory(version: 1, entries: entries.filter {
            let path = URL(fileURLWithPath: $0.projectPath).standardizedFileURL.path
            guard !ids.contains($0.id), !paths.contains(path) else { return false }
            ids.insert($0.id)
            paths.insert(path)
            return true
        })
        history.sortByRecordedDate()
        return history
    }

    /// The library index for one storage location. It never comes back empty while take folders still hold
    /// projects: a missing index is rebuilt from them, and a damaged one is set aside as a backup first.
    /// Throws only when the index exists but cannot be read, so callers never overwrite it blind.
    private func loadLocalProjectHistory(settings: RecordingSettings) throws -> RecordingProjectHistory {
        Self.projectHistoryLock.lock()
        defer { Self.projectHistoryLock.unlock() }
        let url = projectHistoryURL(for: settings)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            let rebuilt = rebuiltProjectHistory(settings: settings)
            if !rebuilt.entries.isEmpty {
                libraryLog.notice("Rebuilt missing library index from \(rebuilt.entries.count) take folders")
                writeRepairedProjectHistory(.init(history: rebuilt, settings: settings))
            }
            return rebuilt
        } catch {
            libraryLog.error("Library index unreadable: \(error.localizedDescription, privacy: .public)")
            throw RecorderError.outputDirectoryUnavailable(
                "BlitzRecorder could not read its project list at \(url.path). Nothing was changed. Check that the drive is connected, then try again."
            )
        }
        do {
            var history = try Self.projectDecoder().decode(RecordingProjectHistory.self, from: data)
            let orphans = takeFolderEntries(.init(settings: settings, excluding: history))
            if !orphans.isEmpty {
                history.entries += orphans
                libraryLog.notice("Added \(orphans.count) take folders missing from the library index")
                writeRepairedProjectHistory(.init(history: history, settings: settings))
            }
            history.sortByRecordedDate()
            return history
        } catch {
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("projects.damaged-\(Int(Date().timeIntervalSince1970)).json")
            try FileManager.default.moveItem(at: url, to: backup)
            let rebuilt = rebuiltProjectHistory(settings: settings)
            libraryLog.error(
                "Library index damaged, kept as \(backup.lastPathComponent, privacy: .public); rebuilt \(rebuilt.entries.count) projects"
            )
            try writeProjectHistory(.init(history: rebuilt, settings: settings))
            return rebuilt
        }
    }

    /// A repair that cannot be written is redone on the next load, so it is logged rather than thrown.
    private func writeRepairedProjectHistory(_ request: ProjectHistoryWriteRequest) {
        do {
            try writeProjectHistory(request)
        } catch {
            libraryLog.error("Could not save the repaired library index: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func rebuiltProjectHistory(settings: RecordingSettings) -> RecordingProjectHistory {
        var history = RecordingProjectHistory(version: 1, entries: takeFolderEntries(.init(
            settings: settings, excluding: RecordingProjectHistory(version: 1, entries: [])
        )))
        history.sortByRecordedDate()
        return history
    }

    private struct TakeFolderScan {
        let settings: RecordingSettings
        let excluding: RecordingProjectHistory
    }

    /// Library entries for take folders the index does not list yet. Only unlisted folders are read, and
    /// folders whose project cannot be read are skipped, not deleted.
    private func takeFolderEntries(_ scan: TakeFolderScan) -> [RecordingProjectHistory.Entry] {
        let listedFolders = Set(scan.excluding.entries.map { URL(fileURLWithPath: $0.takeDirectoryPath).lastPathComponent })
        let listedIDs = Set(scan.excluding.entries.map(\.id))
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: scratchRoot(for: scan.settings), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        return folders.filter { !listedFolders.contains($0.lastPathComponent) }.compactMap { folder in
            let projectURL = folder.appendingPathComponent("project.blitzrecorder.json")
            guard let project = try? loadRecordingProject(at: projectURL), !listedIDs.contains(project.id) else { return nil }
            let savedFolder = URL(fileURLWithPath: project.takeDirectoryPath).standardizedFileURL.resolvingSymlinksInPath()
            let isInPlace = savedFolder == folder.standardizedFileURL.resolvingSymlinksInPath()
            return RecordingProjectHistory.Entry(
                id: project.id, title: project.title, projectPath: isInPlace ? project.projectPath : projectURL.path,
                takeDirectoryPath: isInPlace ? project.takeDirectoryPath : folder.path, finalVideoPath: project.finalVideoPath,
                createdAt: project.createdAt, updatedAt: project.updatedAt, exports: project.exports
            )
        }
    }

    func loadRecordingProject(at url: URL) throws -> RecordingProject {
        if let draft = Self.draft, draft.matches(url) { return draft.project }
        let saved = try savedRecordingProject(at: url)
        // An editor change still waiting to be written is what the project is now, for every reader.
        guard let pending = ProjectSaveQueue.shared.pendingProject(at: url) else { return saved }
        return pending.keepingSavedMetadata(from: saved)
    }

    private func savedRecordingProject(at url: URL) throws -> RecordingProject {
        // Stamped before reading: if the file changes mid-read, the next load sees a new stamp and decodes again.
        let stamp = ProjectFileCache.Stamp(url: url)
        if let stamp, let cached = Self.projectCache.project(path: url.path, stamp: stamp) { return cached }
        let data = try Data(contentsOf: url)
        let project: RecordingProject
        do {
            project = try Self.projectDecoder().decode(RecordingProject.self, from: data)
        } catch {
            project = try RecordingProject.importedPortable(from: data, projectURL: url)
        }
        // Imported videos are found through bookmarks while decoding, so those projects depend on more than
        // their file and are decoded fresh each time; caching them would also keep the original's access open.
        if let stamp, !project.sources.contains(where: { $0.bookmarkData != nil }) {
            Self.projectCache.insert(.init(path: url.path, stamp: stamp, project: project))
        }
        return project
    }

    func renameProject(
        _ request: RecordingProjectRenameRequest
    ) throws -> RecordingProject {
        let title = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw RecorderError.mediaWriteFailed("Enter a recording title.")
        }

        Self.projectWriteLock.lock()
        defer { Self.projectWriteLock.unlock() }
        let project = try loadRecordingProject(at: request.projectURL)
        let renamedProject = Self.updatingMetadata(.init(
            project: project,
            title: title,
            finalVideoPath: project.finalVideoPath,
            exports: project.exports
        ))

        try Self.projectEncoder().encode(renamedProject).write(
            to: request.projectURL,
            options: .atomic
        )
        try upsertProjectHistory(renamedProject, settings: request.settings)
        Self.postProjectEdited(renamedProject)
        return renamedProject
    }

    struct CompletedExportRequest {
        let projectURL: URL
        let record: RecordingProject.ExportRecord
        let settings: RecordingSettings
    }

    func recordCompletedExport(_ request: CompletedExportRequest) throws {
        Self.projectWriteLock.lock()
        defer { Self.projectWriteLock.unlock() }
        let project = try loadRecordingProject(at: request.projectURL)
        let updated = Self.updatingMetadata(.init(
            project: project,
            title: project.title,
            finalVideoPath: request.record.path,
            exports: project.exports.upserting(request.record)
        ))
        try Self.projectEncoder().encode(updated).write(to: request.projectURL, options: .atomic)
        try upsertProjectHistory(updated, settings: request.settings)
        Self.postProjectEdited(updated)
    }

    /// Observers run on the main queue, and posting waits for them. A writer off the main thread usually still
    /// holds `projectWriteLock`, which the main thread may be waiting for, so it posts without waiting.
    static func postProjectEdited(_ project: RecordingProject) {
        let edited = RecordingProjectEdited(projectPath: project.projectPath, editRevision: project.editRevision)
        guard Thread.isMainThread else {
            DispatchQueue.main.async { NotificationCenter.default.post(name: .recordingProjectEdited, object: edited) }
            return
        }
        NotificationCenter.default.post(name: .recordingProjectEdited, object: edited)
    }

    private struct ProjectMetadataUpdate {
        let project: RecordingProject
        let title: String
        let finalVideoPath: String?
        let exports: [RecordingProject.ExportRecord]
    }

    private static func updatingMetadata(_ update: ProjectMetadataUpdate) -> RecordingProject {
        let project = update.project
        var updated = RecordingProject(
            version: project.version, id: project.id, createdAt: project.createdAt, updatedAt: Date(),
            title: update.title, projectPath: project.projectPath, takeDirectoryPath: project.takeDirectoryPath,
            finalVideoPath: update.finalVideoPath, settings: project.settings, sources: project.sources,
            sceneEvents: project.sceneEvents, chapters: project.chapters, editorTimeline: project.editorTimeline,
            editorState: project.editorState, exports: update.exports,
            timelineTrimOffsetSeconds: project.timelineTrimOffsetSeconds,
            sourceTimelineOffsetSeconds: project.sourceTimelineOffsetSeconds,
            timelineEdits: project.timelineEdits, analysis: project.analysis
        )
        updated.editRevision = project.editRevision
        updated.cameraAngles = project.cameraAngles
        updated.programAudioRole = project.programAudioRole
        return updated
    }

    @discardableResult
    func deleteProject(_ request: RecordingProjectDeletionRequest) throws -> RecordingProjectTrashReceipt? {
        let fileManager = FileManager.default
        let librarySettings = projectLibrarySettings(.init(takePath: request.project.takeDirectoryPath, settings: request.settings))
        let outputDirectoryAccess = OutputDirectoryAccess(locations: [librarySettings.sourceStorage])
        guard outputDirectoryAccess.hasSecurityScopedAccess else {
            outputDirectoryAccess.stop()
            throw RecorderError.outputDirectoryUnavailable(
                Self.permissionRecoveryMessage(for: librarySettings.sourceStorage.url)
            )
        }
        defer {
            outputDirectoryAccess.stop()
        }

        let projectDirectory = URL(
            fileURLWithPath: request.project.takeDirectoryPath,
            isDirectory: true
        ).standardizedFileURL
        // Waits for a save in flight; any save after this finds the folder gone, so the recording stays deleted.
        Self.projectWriteLock.lock()
        defer { Self.projectWriteLock.unlock() }
        try validateProjectDeletionTarget(request)

        var receipt: RecordingProjectTrashReceipt?
        if fileManager.fileExists(atPath: projectDirectory.path) {
            switch request.disposition {
            case .trash:
                var trashedURL: NSURL?
                try fileManager.trashItem(at: projectDirectory, resultingItemURL: &trashedURL)
                if let trashedURL {
                    receipt = RecordingProjectTrashReceipt(project: request.project, trashedDirectory: trashedURL as URL)
                }
            case .permanent:
                try fileManager.removeItem(at: projectDirectory)
            }
        }

        Self.projectHistoryLock.lock()
        defer { Self.projectHistoryLock.unlock() }
        do {
            var history = try loadLocalProjectHistory(settings: librarySettings)
            history.entries.removeAll {
                $0.id == request.project.id || $0.projectPath == request.project.projectPath
            }
            try writeProjectHistory(ProjectHistoryWriteRequest(history: history, settings: librarySettings))
        } catch {
            if let receipt {
                try fileManager.moveItem(at: receipt.trashedDirectory, to: projectDirectory)
            }
            throw error
        }
        return receipt
    }

    func restoreProjectFromTrash(_ request: RecordingProjectRestorationRequest) throws {
        let receipt = request.receipt
        let fileManager = FileManager.default
        let librarySettings = projectLibrarySettings(.init(takePath: receipt.project.takeDirectoryPath, settings: request.settings))
        let access = OutputDirectoryAccess(locations: [librarySettings.sourceStorage])
        defer { access.stop() }
        guard access.hasSecurityScopedAccess else {
            throw RecorderError.outputDirectoryUnavailable(Self.permissionRecoveryMessage(for: librarySettings.sourceStorage.url))
        }
        Self.projectWriteLock.lock()
        defer { Self.projectWriteLock.unlock() }
        try validateProjectDeletionTarget(.init(project: receipt.project, settings: request.settings, disposition: .trash))
        let original = URL(fileURLWithPath: receipt.project.takeDirectoryPath, isDirectory: true)
        guard !fileManager.fileExists(atPath: original.path) else {
            throw RecorderError.mediaWriteFailed("A folder already exists for \"\(receipt.project.displayTitle)\". Nothing was replaced.")
        }
        let project = try loadRecordingProject(at: receipt.trashedDirectory.appendingPathComponent("project.blitzrecorder.json"))
        guard project.id == receipt.project.id else {
            throw RecorderError.mediaWriteFailed("The project in Trash no longer matches this recording.")
        }
        try fileManager.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: receipt.trashedDirectory, to: original)
        do {
            try upsertProjectHistory(project, settings: request.settings)
        } catch {
            try fileManager.moveItem(at: original, to: receipt.trashedDirectory)
            throw error
        }
    }

    private func validateProjectDeletionTarget(_ request: RecordingProjectDeletionRequest) throws {
        let directory = URL(fileURLWithPath: request.project.takeDirectoryPath, isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        let librarySettings = projectLibrarySettings(.init(takePath: request.project.takeDirectoryPath, settings: request.settings))
        let root = scratchRoot(for: librarySettings).standardizedFileURL.resolvingSymlinksInPath()
        let metadata = URL(fileURLWithPath: request.project.projectPath).standardizedFileURL.resolvingSymlinksInPath()
        guard directory.deletingLastPathComponent() == root,
            metadata.deletingLastPathComponent() == directory,
            metadata.lastPathComponent == "project.blitzrecorder.json"
        else {
            throw RecorderError.mediaWriteFailed("This project is outside the BlitzRecorder source projects folder.")
        }
        if FileManager.default.fileExists(atPath: metadata.path) {
            guard try loadRecordingProject(at: metadata).id == request.project.id else {
                throw RecorderError.mediaWriteFailed("The project folder belongs to a different recording.")
            }
        }
    }

    func projectHistoryURL(for settings: RecordingSettings) -> URL {
        settings.sourceStorage.url
            .appendingPathComponent("BlitzRecorder Projects", isDirectory: true)
            .appendingPathComponent("projects.json")
    }

    func scratchRoot(for settings: RecordingSettings) -> URL {
        settings.sourceStorage.url.appendingPathComponent("BlitzRecorder Source Takes", isDirectory: true)
    }

    /// Takes in the system temporary folder are deleted by macOS and never belong in a library.
    static func isTemporary(_ path: String) -> Bool {
        let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        let candidate = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        return candidate == temporary || candidate.hasPrefix(temporary.hasSuffix("/") ? temporary : temporary + "/")
    }

    func upsertProjectHistory(_ project: RecordingProject, settings: RecordingSettings) throws {
        let settings = projectLibrarySettings(.init(takePath: project.takeDirectoryPath, settings: settings))
        let indexRoot = settings.sourceStorage.url.standardizedFileURL.resolvingSymlinksInPath()
        if Self.isTemporary(project.takeDirectoryPath), !Self.isTemporary(indexRoot.path) { return }
        Self.projectHistoryLock.lock()
        defer { Self.projectHistoryLock.unlock() }
        let access = OutputDirectoryAccess(locations: [settings.sourceStorage])
        defer { access.stop() }
        guard access.hasSecurityScopedAccess else {
            throw RecorderError.outputDirectoryUnavailable(Self.permissionRecoveryMessage(for: settings.sourceStorage.url))
        }
        var history = try indexForUpdate(settings: settings)
        history.entries.removeAll { $0.id == project.id || $0.projectPath == project.projectPath }
        history.entries.insert(RecordingProjectHistory.Entry(project), at: 0)
        history.sortByRecordedDate()
        try writeProjectHistory(ProjectHistoryWriteRequest(
            history: history,
            settings: settings
        ))
    }

    /// The saved index as it is, for changing one entry. Every save lands here, so it skips listing the take
    /// folders; library loads add any folder the index misses. A missing or damaged index takes the repair path.
    private func indexForUpdate(settings: RecordingSettings) throws -> RecordingProjectHistory {
        if let data = try? Data(contentsOf: projectHistoryURL(for: settings)),
           let history = try? Self.projectDecoder().decode(RecordingProjectHistory.self, from: data) {
            return history
        }
        return try loadLocalProjectHistory(settings: settings)
    }

    private struct ProjectLibrarySettingsRequest {
        let takePath: String
        let settings: RecordingSettings
    }

    private func projectLibrarySettings(_ request: ProjectLibrarySettingsRequest) -> RecordingSettings {
        let root = URL(fileURLWithPath: request.takePath).deletingLastPathComponent().deletingLastPathComponent()
            .standardizedFileURL.resolvingSymlinksInPath()
        var settings = request.settings
        if let location = settings.projectLibraries.first(where: { $0.url.standardizedFileURL.resolvingSymlinksInPath() == root }) {
            settings.projectLibrary = location
        }
        return settings
    }

    private func writeProjectHistory(_ request: ProjectHistoryWriteRequest) throws {
        let historyURL = projectHistoryURL(for: request.settings)
        try FileManager.default.createDirectory(
            at: historyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try Self.projectEncoder().encode(request.history)
        try data.write(to: historyURL, options: .atomic)
    }

    static func projectEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func projectDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension Array where Element == RecordingProject.ExportRecord {
    func upserting(_ record: RecordingProject.ExportRecord) -> [RecordingProject.ExportRecord] {
        var exports = filter { $0.path != record.path }
        exports.append(record)
        exports.sort { $0.createdAt < $1.createdAt }
        return exports
    }
}

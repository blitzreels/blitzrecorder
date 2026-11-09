import Darwin
import Foundation

enum TakeRecoveryFiles {
    static func directory(takeDirectory: URL) -> URL {
        takeDirectory.appendingPathComponent("recovery", isDirectory: true)
    }

    static func journal(takeDirectory: URL) -> URL {
        directory(takeDirectory: takeDirectory).appendingPathComponent("journal.jsonl")
    }

    static func attempts(takeDirectory: URL) -> URL {
        directory(takeDirectory: takeDirectory).appendingPathComponent("attempts")
    }

    static func recoveredMarker(takeDirectory: URL) -> URL {
        directory(takeDirectory: takeDirectory).appendingPathComponent("recovered.json")
    }

    static func audioSegments(audioURL: URL) -> URL {
        directory(takeDirectory: audioURL.deletingLastPathComponent())
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent(audioURL.deletingPathExtension().lastPathComponent, isDirectory: true)
    }
}

enum DurableFile {
    static func flush(_ url: URL) {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else { return }
        flush(descriptor: descriptor)
        close(descriptor)
    }

    static func flush(descriptor: Int32) {
        if fcntl(descriptor, F_FULLFSYNC) != 0 { fsync(descriptor) }
    }
}

struct TakeRecoveryJournalEntry: Codable {
    enum Kind: String, Codable {
        case began, timing, scenes
    }

    struct Source: Codable, Equatable {
        let role: String
        let path: String
    }

    let kind: Kind
    let date: Date
    var processID: Int32?
    var sources: [Source]?
    var timelineTrimOffsetSeconds: Double?
    var sceneEvents: [RecordingProject.SceneEventSnapshot]?
}

/// Everything a take needs to be rebuilt after a crash. Each change reaches the disk as soon as it happens, and
/// the journal stays locked while the take records, so another copy of the app never treats a live take as crashed.
final class TakeRecoveryJournal: @unchecked Sendable {
    private let queue = DispatchQueue(label: "blitzrecorder.take-recovery-journal", qos: .userInitiated)
    private let directory: URL
    private var descriptor: Int32

    init(take: RecordingTake) throws {
        directory = TakeRecoveryFiles.directory(takeDirectory: take.scratchDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = TakeRecoveryFiles.journal(takeDirectory: take.scratchDirectory)
        descriptor = open(url.path, O_CREAT | O_WRONLY | O_APPEND, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        _ = flock(descriptor, LOCK_EX | LOCK_NB)
        DurableFile.flush(directory)
        var entry = TakeRecoveryJournalEntry(kind: .began, date: Date())
        entry.processID = ProcessInfo.processInfo.processIdentifier
        entry.sources = Self.sources(of: take)
        append(entry)
    }

    deinit {
        if descriptor >= 0 { close(descriptor) }
    }

    func recordTiming(timelineTrimOffsetSeconds: Double) {
        var entry = TakeRecoveryJournalEntry(kind: .timing, date: Date())
        entry.timelineTrimOffsetSeconds = timelineTrimOffsetSeconds
        append(entry)
    }

    func recordScenes(_ events: [RecordingSceneEvent]) {
        guard !events.isEmpty else { return }
        var entry = TakeRecoveryJournalEntry(kind: .scenes, date: Date())
        entry.sceneEvents = events.map(RecordingProject.SceneEventSnapshot.init)
        append(entry)
    }

    func discard() {
        queue.sync {
            if descriptor >= 0 { close(descriptor) }
            descriptor = -1
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func append(_ entry: TakeRecoveryJournalEntry) {
        queue.async { [self] in
            guard descriptor >= 0, let json = try? Self.encoder.encode(entry) else { return }
            // The leading newline closes off a line left unfinished by a failed write.
            let line = Data("\n".utf8) + json + Data("\n".utf8)
            let wrote = line.withUnsafeBytes { bytes -> Bool in
                var offset = 0
                while offset < bytes.count {
                    let count = write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                    guard count > 0 else { return false }
                    offset += count
                }
                return true
            }
            if wrote {
                DurableFile.flush(descriptor: descriptor)
            } else {
                NSLog("Recovery journal could not be written: %d", errno)
            }
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static func sources(of take: RecordingTake) -> [TakeRecoveryJournalEntry.Source] {
        ([("screen", take.screenURL), ("camera", take.cameraURL), ("microphone", take.microphoneCaptureURL),
          ("systemAudio", take.systemAudioURL)] + (take.cameraAngleFiles + take.microphoneTrackFiles).map { ($0.role, $0.url) })
            .map { .init(role: $0.0, path: $0.1.path) }
    }
}

struct TakeRecoveryJournalContents {
    private(set) var processID: Int32?
    private(set) var timelineTrimOffsetSeconds: Double?
    private(set) var sceneEvents: [RecordingProject.SceneEventSnapshot] = []

    init(url: URL) throws {
        let decoder = TakeFileStore.projectDecoder()
        let lines = try Data(contentsOf: url).split(separator: UInt8(ascii: "\n"))
        for line in lines {
            guard let entry = try? decoder.decode(TakeRecoveryJournalEntry.self, from: Data(line)) else { continue }
            switch entry.kind {
            case .began:
                processID = entry.processID
            case .timing:
                timelineTrimOffsetSeconds = entry.timelineTrimOffsetSeconds
            case .scenes:
                sceneEvents = entry.sceneEvents ?? sceneEvents
            }
        }
    }
}

/// Held while a take is recovered. It cannot be taken while the app that recorded the take is still running.
final class TakeRecoveryLock {
    private let descriptor: Int32

    struct Request {
        let journalURL: URL
        let ownerProcessID: Int32?
    }

    init?(_ request: Request) {
        let descriptor = open(request.journalURL.path, O_RDWR)
        guard descriptor >= 0 else { return nil }
        if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            let lockIsHeld = errno == EWOULDBLOCK
            let ownerIsAlive = request.ownerProcessID.map { kill($0, 0) == 0 } ?? false
            guard !lockIsHeld, !ownerIsAlive else {
                close(descriptor)
                return nil
            }
        }
        self.descriptor = descriptor
    }

    deinit {
        close(descriptor)
    }
}

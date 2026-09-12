import Foundation

struct ProjectLibraryFilters: Equatable {
    enum Recorded: String, CaseIterable {
        case any = "Any date", today = "Today", week = "Last 7 days", month = "Last 30 days"
    }

    enum Duration: String, CaseIterable {
        case any = "Any duration", short = "Under 1 minute", medium = "1–10 minutes"
        case long = "10–60 minutes", hour = "1 hour or longer"

        func matches(_ seconds: Double?) -> Bool {
            if self == .any { return true }
            guard let seconds, seconds.isFinite, seconds >= 0 else { return false }
            switch self {
            case .any: return true
            case .short: return seconds < 60
            case .medium: return seconds >= 60 && seconds < 600
            case .long: return seconds >= 600 && seconds < 3_600
            case .hour: return seconds >= 3_600
            }
        }
    }

    enum Quality: String, CaseIterable {
        case any = "Any quality", hd = "720p or higher", fullHD = "1080p or higher"
        case qhd = "1440p or higher", ultraHD = "4K or higher"

        var minimumPixels: Int {
            switch self {
            case .any: 0
            case .hd: 720
            case .fullHD: 1080
            case .qhd: 1440
            case .ultraHD: 2160
            }
        }
    }

    enum Source: String, CaseIterable {
        case any = "Any source", screen = "Screen", camera = "Camera", audio = "Audio only"
    }

    enum Transcript: String, CaseIterable {
        case any = "Any transcript status", ready = "Transcript ready", missing = "No transcript yet"
    }

    enum Sort: String, CaseIterable {
        case newest = "Newest first", oldest = "Oldest first", longest = "Longest first"
        case shortest = "Shortest first", title = "Title A–Z"
    }

    var recorded: Recorded = .any
    var duration: Duration = .any
    var quality: Quality = .any
    var source: Source = .any
    var transcript: Transcript = .any
    var sort: Sort = .newest

    var activeCount: Int {
        [recorded != .any, duration != .any, quality != .any, source != .any, transcript != .any]
            .filter { $0 }.count
    }

    struct Request {
        let projects: [RecordingProjectHistory.Entry]
        let metadata: [UUID: ProjectLibraryMetadata]
        let transcriptReadyIDs: Set<UUID>
        let now: Date
        let calendar: Calendar
    }

    func apply(_ request: Request) -> [RecordingProjectHistory.Entry] {
        let days: Int? = switch recorded {
        case .any: nil
        case .today: 0
        case .week: -6
        case .month: -29
        }
        let cutoff = days.flatMap {
            request.calendar.date(byAdding: .day, value: $0, to: request.calendar.startOfDay(for: request.now))
        }
        let matches = request.projects.filter { project in
            let metadata = request.metadata[project.id]
            if let cutoff, project.recordedAt < cutoff { return false }
            guard duration.matches(metadata?.durationSeconds) else { return false }
            if quality != .any, (metadata?.videoQuality?.shortEdge ?? 0) < quality.minimumPixels { return false }
            let roles = metadata?.sourceRoles ?? []
            switch source {
            case .any: break
            case .screen: if !roles.contains("screen") { return false }
            case .camera: if !roles.contains("camera") { return false }
            case .audio:
                if !roles.isDisjoint(with: ["screen", "camera"])
                    || roles.isDisjoint(with: ["microphone", "systemAudio"]) { return false }
            }
            let ready = request.transcriptReadyIDs.contains(project.id)
            return transcript == .any || (transcript == .ready ? ready : !ready)
        }
        return matches.sorted { lhs, rhs in
            switch sort {
            case .newest, .oldest:
                if lhs.recordedAt != rhs.recordedAt {
                    return sort == .newest ? lhs.recordedAt > rhs.recordedAt : lhs.recordedAt < rhs.recordedAt
                }
            case .longest, .shortest:
                let left = request.metadata[lhs.id]?.durationSeconds
                let right = request.metadata[rhs.id]?.durationSeconds
                if let left, let right, left != right { return sort == .longest ? left > right : left < right }
                if (left == nil) != (right == nil) { return left != nil }
            case .title:
                let order = lhs.displayTitle.localizedStandardCompare(rhs.displayTitle)
                if order != .orderedSame { return order == .orderedAscending }
            }
            if lhs.recordedAt != rhs.recordedAt { return lhs.recordedAt > rhs.recordedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

import AVFoundation
import Foundation
import Vision

struct PrivacyFinding: Equatable, Identifiable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case email, phone, card, iban, secret, notification, passwordManager

        var title: String {
            switch self {
            case .email: "Email"
            case .phone: "Phone number"
            case .card: "Card number"
            case .iban: "Bank account"
            case .secret: "Key or password"
            case .notification: "Notification"
            case .passwordManager: "Password app"
            }
        }

        var symbolName: String {
            switch self {
            case .email: "envelope"
            case .phone: "phone"
            case .card: "creditcard"
            case .iban: "building.columns"
            case .secret: "key"
            case .notification: "bell"
            case .passwordManager: "lock"
            }
        }
    }

    let id: UUID
    let kind: Kind
    let key: String
    let preview: String
    var frame: CGRect
    var start: Double
    var end: Double
}

enum PrivacyTextClassifier {
    struct Match: Equatable {
        let kind: PrivacyFinding.Kind
        let range: Range<String.Index>
    }

    private static let email = try! NSRegularExpression(
        pattern: #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#, options: .caseInsensitive)
    private static let token = try! NSRegularExpression(pattern: #"(?:sk-(?:proj-|ant-)?[A-Za-z0-9_\-]{16,}"#
        + #"|[sr]k_(?:live|test)_[A-Za-z0-9]{16,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}"#
        + #"|xox[abprs]-[A-Za-z0-9\-]{10,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_\-]{35}"#
        + #"|eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,})"#)
    private static let assignment = try! NSRegularExpression(
        pattern: #"\b(?:api[_ -]?key|secret|token|password|passwd|pwd|access[_ -]?key|private[_ -]?key)\b\s*[:=]\s*["']?([^\s"']{6,})"#,
        options: .caseInsensitive)
    private static let cardDigits = try! NSRegularExpression(pattern: #"\b(?:\d[ \-]?){12,18}\d\b"#)
    private static let iban = try! NSRegularExpression(pattern: #"\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]){11,30}\b"#)
    private static let phone = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue)

    static func matches(in text: String) -> [Match] {
        var found: [Match] = []
        func add(_ kind: PrivacyFinding.Kind, _ nsRange: NSRange) {
            guard let range = Range(nsRange, in: text),
                  !found.contains(where: { $0.range.overlaps(range) }) else { return }
            found.append(.init(kind: kind, range: range))
        }
        let whole = NSRange(text.startIndex..., in: text)
        token.matches(in: text, range: whole).forEach { add(.secret, $0.range) }
        assignment.matches(in: text, range: whole).forEach { add(.secret, $0.range(at: 1)) }
        email.matches(in: text, range: whole).forEach { add(.email, $0.range) }
        iban.matches(in: text, range: whole)
            .filter { Range($0.range, in: text).map { isIBAN(String(text[$0])) } ?? false }
            .forEach { add(.iban, $0.range) }
        cardDigits.matches(in: text, range: whole)
            .filter { Range($0.range, in: text).map { passesLuhn(String(text[$0])) } ?? false }
            .forEach { add(.card, $0.range) }
        phone?.matches(in: text, range: whole)
            .filter { Range($0.range, in: text).map { text[$0].filter(\.isNumber).count >= 9 } ?? false }
            .forEach { add(.phone, $0.range) }
        return found
    }

    static func preview(_ request: PreviewRequest) -> String {
        let text = request.text.trimmingCharacters(in: .whitespaces)
        switch request.kind {
        case .email:
            guard let at = text.firstIndex(of: "@") else { return "•••" }
            return "\(text.prefix(1))•••\(text[at...])"
        case .card, .phone:
            return "•••• \(text.filter(\.isNumber).suffix(4))"
        case .iban, .secret:
            return "\(text.prefix(4))•••"
        case .notification, .passwordManager:
            return text
        }
    }

    struct PreviewRequest {
        let kind: PrivacyFinding.Kind
        let text: String
    }

    private static func passesLuhn(_ text: String) -> Bool {
        let digits = text.compactMap(\.wholeNumberValue)
        guard (13...19).contains(digits.count), Set(digits).count > 1 else { return false }
        let sum = digits.reversed().enumerated().reduce(0) { total, item in
            guard item.offset % 2 == 1 else { return total + item.element }
            let doubled = item.element * 2
            return total + (doubled > 9 ? doubled - 9 : doubled)
        }
        return sum % 10 == 0
    }

    private static func isIBAN(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "")
        guard (15...34).contains(compact.count) else { return false }
        let rearranged = compact.dropFirst(4) + compact.prefix(4)
        var remainder = 0
        for character in rearranged {
            let value: Int
            if let digit = character.wholeNumberValue { value = digit }
            else if let ascii = character.asciiValue, (65...90).contains(ascii) { value = Int(ascii) - 55 }
            else { return false }
            for digit in String(value) { remainder = (remainder * 10 + digit.wholeNumberValue!) % 97 }
        }
        return remainder == 1
    }
}

enum PrivacyScanner {
    struct Request: Sendable {
        let videoURL: URL
        let sourceOffset: Double
        let duration: Double
        let onProgress: @Sendable (Double) -> Void
    }

    private struct Detection {
        let kind: PrivacyFinding.Kind
        let key: String
        let preview: String
        let frame: CGRect
    }

    private static let warmUpTask = Task.detached(priority: .utility) {
        guard let context = CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let image = context.makeImage() else { return }
        _ = detect(.init(image: image, band: nil))
    }

    /// Text recognition loads its model on first use, which can take half a minute after an install or update.
    static func warmUp() {
        _ = warmUpTask
    }

    static func scan(_ request: Request) async throws -> [PrivacyFinding] {
        let asset = AVURLAsset(url: request.videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 2560, height: 2560)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.3, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.3, preferredTimescale: 600)
        let interval = request.duration > 1_200 ? 2.0 : 1.0
        let times = stride(from: 0, to: max(request.duration, 0.01), by: interval)
            .map { CMTime(seconds: $0 + request.sourceOffset, preferredTimescale: 600) }

        var merger = FindingMerger(interval: interval)
        var previousThumbnail: [UInt8]?
        var previousDetections: [Detection] = []
        var batch: [Job] = []
        var completed = 0
        let batchSize = max(2, min(4, ProcessInfo.processInfo.activeProcessorCount / 2))

        func flush() async throws {
            guard !batch.isEmpty else { return }
            let jobs = batch
            batch = []
            let recognized = try await withThrowingTaskGroup(of: (Int, [Detection]).self) { group in
                for (position, job) in jobs.enumerated() {
                    group.addTask {
                        try Task.checkCancellation()
                        switch job.work {
                        case .reuse: return (position, [])
                        case .full: return (position, Self.detect(.init(image: job.image, band: nil)))
                        case .bands(let bands):
                            return (position, bands.flatMap { Self.detect(.init(image: job.image, band: $0)) })
                        }
                    }
                }
                var results = [[Detection]](repeating: [], count: jobs.count)
                for try await (position, detections) in group { results[position] = detections }
                return results
            }
            for (job, found) in zip(jobs, recognized) {
                let detections: [Detection]
                switch job.work {
                case .reuse: detections = previousDetections
                case .full: detections = found
                case .bands(let bands):
                    let kept = previousDetections.filter { detection in
                        !bands.contains { $0.contains(detection.frame) }
                    }
                    detections = kept + found.filter { detection in
                        !kept.contains { $0.key == detection.key && Self.overlap($0.frame, detection.frame) > 0.5 }
                    }
                }
                previousDetections = detections
                merger.add(.init(time: job.time, detections: detections))
            }
            completed += jobs.count
            request.onProgress(Double(completed) / Double(max(1, times.count)))
        }

        for await result in generator.images(for: times) {
            try Task.checkCancellation()
            guard let image = try? result.image else {
                completed += 1
                continue
            }
            let thumbnail = Self.thumbnail(image)
            let work: Work
            if let previousThumbnail, let thumbnail {
                work = Self.changedWork(.init(previous: previousThumbnail, current: thumbnail))
            } else {
                work = .full
            }
            previousThumbnail = thumbnail
            batch.append(.init(time: max(0, result.requestedTime.seconds - request.sourceOffset), image: image, work: work))
            if batch.count >= batchSize { try await flush() }
        }
        try await flush()
        return merger.finish(duration: request.duration)
    }

    private enum Work {
        case reuse
        case full
        case bands([CGRect])
    }

    private struct Job {
        let time: Double
        let image: CGImage
        let work: Work
    }

    private struct FindingMerger {
        let interval: Double
        private var findings: [PrivacyFinding] = []
        private var active: [Int] = []

        init(interval: Double) {
            self.interval = interval
        }

        struct Sample {
            let time: Double
            let detections: [Detection]
        }

        mutating func add(_ sample: Sample) {
            var seen: Set<Int> = []
            for detection in sample.detections {
                if let match = active.first(where: { position in
                    !seen.contains(position) && findings[position].key == detection.key
                        && PrivacyScanner.overlap(findings[position].frame, detection.frame) > 0.5
                }) {
                    findings[match].end = sample.time
                    findings[match].frame = findings[match].frame.union(detection.frame)
                    seen.insert(match)
                } else {
                    findings.append(.init(id: UUID(), kind: detection.kind, key: detection.key, preview: detection.preview,
                                          frame: detection.frame, start: max(0, sample.time - interval), end: sample.time))
                    seen.insert(findings.count - 1)
                }
            }
            for position in active where !seen.contains(position) {
                findings[position].end = sample.time
            }
            active = Array(seen)
        }

        func finish(duration: Double) -> [PrivacyFinding] {
            var result = findings
            for position in active { result[position].end = duration }
            return result.filter { $0.end > $0.start }
        }
    }

    private static let thumbnailWidth = 128
    private static let thumbnailHeight = 72
    private static let changeThreshold = 8

    private struct ChangeRequest {
        let previous: [UInt8]
        let current: [UInt8]
    }

    private static func changedWork(_ request: ChangeRequest) -> Work {
        guard request.previous.count == request.current.count else { return .full }
        var changedRows: [Int] = []
        for row in 0..<thumbnailHeight {
            let start = row * thumbnailWidth
            for column in 0..<thumbnailWidth
            where abs(Int(request.previous[start + column]) - Int(request.current[start + column])) >= changeThreshold {
                changedRows.append(row)
                break
            }
        }
        guard !changedRows.isEmpty else { return .reuse }
        let margin = 2
        var ranges: [ClosedRange<Int>] = []
        for row in changedRows {
            let expanded = max(0, row - margin)...min(thumbnailHeight - 1, row + margin)
            if let last = ranges.last, expanded.lowerBound <= last.upperBound + 1 {
                ranges[ranges.count - 1] = last.lowerBound...max(last.upperBound, expanded.upperBound)
            } else {
                ranges.append(expanded)
            }
        }
        let covered = ranges.reduce(0) { $0 + $1.count }
        guard Double(covered) / Double(thumbnailHeight) < 0.5 else { return .full }
        return .bands(ranges.map { range in
            CGRect(x: 0, y: Double(range.lowerBound) / Double(thumbnailHeight),
                   width: 1, height: Double(range.count) / Double(thumbnailHeight))
        })
    }

    struct SignalRequest {
        let track: RecordingPrivacySignalTrack
        let trimOffset: Double
        let duration: Double
    }

    static func findings(_ request: SignalRequest) -> [PrivacyFinding] {
        var findings: [PrivacyFinding] = []
        var lastSeen: [UInt32: (index: Int, time: Double)] = [:]
        for signal in request.track.signals.sorted(by: { $0.time < $1.time }) {
            let time = signal.time - request.trimOffset
            let kind: PrivacyFinding.Kind = signal.kind == .notification ? .notification : .passwordManager
            if let last = lastSeen[signal.windowID], time - last.time <= 1.5,
               overlap(findings[last.index].frame, signal.frame) > 0.5 {
                findings[last.index].end = min(request.duration, time + 0.5)
                findings[last.index].frame = findings[last.index].frame.union(signal.frame)
                lastSeen[signal.windowID] = (last.index, time)
            } else {
                findings.append(.init(id: UUID(), kind: kind, key: "\(signal.kind.rawValue)-\(signal.windowID)",
                                      preview: signal.app, frame: signal.frame,
                                      start: max(0, time - 0.5), end: min(request.duration, time + 0.5)))
                lastSeen[signal.windowID] = (findings.count - 1, time)
            }
        }
        return findings.filter { $0.end > $0.start && $0.end > 0 }
    }

    private struct DetectRequest {
        let image: CGImage
        let band: CGRect?
    }

    private static func detect(_ request: DetectRequest) -> [Detection] {
        let band = request.band ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        let height = Double(request.image.height)
        let pixels = CGRect(x: 0, y: (band.minY * height).rounded(.down), width: Double(request.image.width),
                            height: (band.height * height).rounded(.up))
        guard let image = request.band == nil ? request.image : request.image.cropping(to: pixels) else { return [] }
        let top = pixels.minY / height
        let scale = Double(image.height) / height
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.usesLanguageCorrection = false
        guard (try? VNImageRequestHandler(cgImage: image).perform([text])) != nil else { return [] }
        var detections: [Detection] = []
        for observation in text.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            for match in PrivacyTextClassifier.matches(in: candidate.string) {
                let matched = String(candidate.string[match.range])
                let local = (try? candidate.boundingBox(for: match.range))?.boundingBox ?? observation.boundingBox
                let box = CGRect(x: local.minX, y: top + (1 - local.maxY) * scale,
                                 width: local.width, height: local.height * scale)
                let padX = box.height * 0.35
                let padY = box.height * 0.3
                let frame = box.insetBy(dx: -padX, dy: -padY).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
                guard !frame.isNull, !frame.isEmpty else { continue }
                detections.append(.init(
                    kind: match.kind,
                    key: "\(match.kind.rawValue)-\(matched.lowercased().filter { !$0.isWhitespace })",
                    preview: PrivacyTextClassifier.preview(.init(kind: match.kind, text: matched)),
                    frame: frame))
            }
        }
        return detections
    }

    private static func thumbnail(_ image: CGImage) -> [UInt8]? {
        let width = thumbnailWidth, height = thumbnailHeight
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? pixels : nil
    }

    static func overlap(_ lhs: CGRect, _ rhs: CGRect) -> Double {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        let smaller = min(lhs.width * lhs.height, rhs.width * rhs.height)
        return Double(intersection.width * intersection.height / max(smaller, 0.000001))
    }
}

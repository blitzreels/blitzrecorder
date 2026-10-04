import Foundation

struct ProjectRenameDraft {
    struct Request {
        let original: String
        let resolved: ProjectFolderTitle
    }

    let original: String
    let folder: ProjectFolderPath?
    let hasLesson: Bool
    private let originalCode: String?
    private let initialCode: ProjectLessonCode?
    var title: String
    var module: String
    var lesson: String

    init(_ request: Request) {
        original = request.original
        folder = request.resolved.folder
        initialCode = request.resolved.code
        hasLesson = initialCode != nil
        title = request.resolved.title
        module = initialCode.map { ProjectLessonCode.number($0.module) } ?? ""
        lesson = initialCode.map { ProjectLessonCode.number($0.lesson) } ?? ""
        originalCode = ProjectFolderTitle.segments(request.original).first { ProjectLessonCode($0) != nil }
    }

    var validationMessage: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter a recording title." }
        if hasLesson && (Self.number(module) == nil || Self.number(lesson) == nil) {
            return "Use whole numbers from 0 to 9999 for module and lesson."
        }
        return nil
    }

    var proposedTitle: String? {
        guard validationMessage == nil else { return nil }
        var segments = folder?.segments ?? []
        if hasLesson, let moduleNumber = Self.number(module), let lessonNumber = Self.number(lesson) {
            if moduleNumber == initialCode?.module, lessonNumber == initialCode?.lesson, let originalCode {
                segments.append(originalCode)
            } else {
                let modulePrefix = originalCode?.first.map(String.init) ?? "M"
                let lessonPrefix = originalCode?.first(where: { "ELel".contains($0) }).map(String.init) ?? "L"
                segments.append("\(modulePrefix)\(ProjectLessonCode.number(moduleNumber))\(lessonPrefix)\(ProjectLessonCode.number(lessonNumber))")
            }
        }
        segments.append(title.trimmingCharacters(in: .whitespacesAndNewlines))
        return segments.joined(separator: ProjectFolderPath.separator)
    }

    private static func number(_ value: String) -> Int? {
        guard !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }),
              let number = Int(value), (0...9999).contains(number) else { return nil }
        return number
    }
}

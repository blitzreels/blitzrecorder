import Foundation

struct StudioPagePreference {
    enum Page: String {
        case record
        case projects
        case edit
    }

    struct Saved: Equatable {
        let page: Page
        let projectID: UUID?
    }

    private static let pageKey = "studio.lastPage.v1"
    private static let projectKey = "studio.lastEditedProjectID.v1"

    let defaults: UserDefaults

    func load() -> Saved? {
        guard let page = defaults.string(forKey: Self.pageKey).flatMap(Page.init(rawValue:)) else { return nil }
        let projectID = defaults.string(forKey: Self.projectKey).flatMap(UUID.init(uuidString:))
        return Saved(page: page, projectID: projectID)
    }

    func save(_ saved: Saved) {
        defaults.set(saved.page.rawValue, forKey: Self.pageKey)
        defaults.set(saved.projectID?.uuidString, forKey: Self.projectKey)
    }
}

extension StudioPagePreference.Page {
    init(_ mode: RecorderStudioMode) {
        switch mode {
        case .record: self = .record
        case .projects: self = .projects
        case .edit: self = .edit
        }
    }
}

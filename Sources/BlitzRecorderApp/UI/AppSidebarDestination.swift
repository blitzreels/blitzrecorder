import SwiftUI

enum AppSidebarDestination: Hashable {
    case recordings
    case shared
    case folder(ProjectFolderScope)
    case editor
    case record
    case settings

    struct State {
        let studioMode: RecorderStudioMode
        let isShowingSettings: Bool
        let navigation: ProjectLibraryNavigationState
    }

    init(_ state: State) {
        if state.isShowingSettings {
            self = .settings
            return
        }
        switch state.studioMode {
        case .record: self = .record
        case .edit: self = .editor
        case .projects:
            if state.navigation.section == .shared {
                self = .shared
            } else if let scope = state.navigation.folderScope {
                self = .folder(scope)
            } else {
                self = .recordings
            }
        }
    }
}

extension RecorderViewModel {
    var sidebarDestination: AppSidebarDestination {
        .init(.init(studioMode: studioMode, isShowingSettings: isShowingSettings, navigation: projectLibraryNavigation))
    }

    func showSidebarDestination(_ destination: AppSidebarDestination) {
        switch destination {
        case .recordings: showLibrary(.init(section: .recordings, folderScope: nil))
        case .shared: showLibrary(.init(section: .shared, folderScope: nil))
        case .folder(let scope):
            showLibrary(.init(section: .recordings, folderScope: scope))
        case .editor: openEditor()
        case .record: showRecorder()
        case .settings: showSettings(nil)
        }
    }

    private struct LibraryScope {
        let section: ProjectLibraryNavigationState.Section
        let folderScope: ProjectFolderScope?
    }

    private func showLibrary(_ scope: LibraryScope) {
        guard canShowProjects else { return }
        projectLibraryNavigation.section = scope.section
        projectLibraryNavigation.folderScope = scope.folderScope
        if studioMode == .projects {
            dismissSettings()
        } else {
            showProjects()
        }
    }

    func startNewRecording() {
        guard state == .idle, session.countdownRemaining == nil else { return showRecorder() }
        switch sidebarDestination {
        case .folder(let scope):
            recordInFolder(recordTarget(scope))
        case .recordings, .shared:
            libraryActions.folderRecordTarget = nil
            showRecorder()
        case .editor, .record, .settings:
            showRecorder()
        }
    }

    var newRecordingFolder: ProjectFolderScope? {
        guard state == .idle, case .folder(let scope) = sidebarDestination else { return nil }
        return scope
    }

    var canOpenEditorFromSidebar: Bool {
        canOpenEditor && canOpenProjectEditor
    }
}

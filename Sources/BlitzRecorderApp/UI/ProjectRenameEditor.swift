import SwiftUI

struct ProjectRecordingRenameEditor: View {
    let project: RecordingProjectHistory.Entry
    let index: ProjectFolderIndex
    let library: [RecordingProjectHistory.Entry]
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @State private var draft: ProjectRenameDraft
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case title, module, lesson }

    struct Configuration {
        let project: RecordingProjectHistory.Entry
        let index: ProjectFolderIndex
        let library: [RecordingProjectHistory.Entry]
        let onSave: (String) -> Void
        let onCancel: () -> Void
    }

    init(_ configuration: Configuration) {
        project = configuration.project
        index = configuration.index
        library = configuration.library
        onSave = configuration.onSave
        onCancel = configuration.onCancel
        _draft = State(initialValue: ProjectRenameDraft(.init(
            original: configuration.project.title,
            resolved: configuration.index.resolved(configuration.project)
        )))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(draft.hasLesson ? "Rename lesson" : "Rename recording")
                .font(BlitzType.title)
            ProjectRenameContext(path: draft.folder?.displayPath ?? "Recordings")
            if draft.hasLesson {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Module").font(BlitzType.strong)
                        TextField("Module", text: $draft.module)
                            .focused($focusedField, equals: .module)
                            .accessibilityLabel("Module number")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Lesson").font(BlitzType.strong)
                        TextField("Lesson", text: $draft.lesson)
                            .focused($focusedField, equals: .lesson)
                            .accessibilityLabel("Lesson number")
                    }
                    Spacer(minLength: 200)
                }
                .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Title").font(BlitzType.strong)
                TextField("Recording title", text: $draft.title, axis: .vertical)
                    .lineLimit(2...4)
                    .focused($focusedField, equals: .title)
                    .accessibilityLabel("Recording title")
            }
            ProjectRenamePreview(title: "Full name", value: draft.proposedTitle ?? project.title)
            if let message = draft.validationMessage {
                Text(message).font(BlitzType.caption).foregroundStyle(BlitzUI.recordRed)
            } else if hasDuplicateLesson {
                Label("This lesson number is already used in this module.", systemImage: "exclamationmark.triangle")
                    .font(BlitzType.caption).foregroundStyle(.orange)
            }
            Text("Only this recording is renamed. Its folder and other lessons stay in place.")
                .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).blitzButton(.secondary).keyboardShortcut(.cancelAction)
                Button("Rename") {
                    if let title = draft.proposedTitle { onSave(title) }
                }
                .blitzButton(.accent).keyboardShortcut(.defaultAction)
                .disabled(draft.proposedTitle == nil || draft.proposedTitle == project.title)
            }
        }
        .textFieldStyle(.roundedBorder)
        .controlSize(.large)
        .padding(24)
        .frame(width: 560)
        .onAppear { focusedField = draft.hasLesson ? .lesson : .title }
    }

    private var hasDuplicateLesson: Bool {
        guard draft.hasLesson, let module = Int(draft.module), let lesson = Int(draft.lesson) else { return false }
        return library.contains { entry in
            let resolved = index.resolved(entry)
            return entry.id != project.id && resolved.folder == draft.folder
                && resolved.code?.module == module && resolved.code?.lesson == lesson
        }
    }
}

struct ProjectFolderNameEditor: View {
    let prompt: ProjectFolderPrompt
    @Binding var name: String
    let affectedCount: Int
    let onSave: () -> Void
    let onCancel: () -> Void
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(prompt.title).font(BlitzType.title)
            ProjectRenameContext(path: parent?.displayPath ?? "Recordings")
            VStack(alignment: .leading, spacing: 6) {
                Text("Folder name").font(BlitzType.strong)
                TextField("Folder name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFocused)
                    .accessibilityLabel("Folder name")
            }
            ProjectRenamePreview(title: "Folder path", value: proposedPath)
            if !name.isEmpty && !ProjectFolderPath.isValidName(name) {
                Text("Use a name without /, : or ‘ - ’. Lesson codes belong to recordings.")
                    .font(BlitzType.caption).foregroundStyle(BlitzUI.recordRed)
            }
            Text(scopeDescription).font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).blitzButton(.secondary).keyboardShortcut(.cancelAction)
                Button(prompt.actionTitle, action: onSave).blitzButton(.accent).keyboardShortcut(.defaultAction)
                    .disabled(!ProjectFolderPath.isValidName(name) || isUnchanged)
            }
        }
        .controlSize(.large)
        .padding(24)
        .frame(width: 560)
        .onAppear { isNameFocused = true }
    }

    private var parent: ProjectFolderPath? {
        switch prompt {
        case .create(let parent, _): parent
        case .rename(let path): path.parent
        }
    }

    private var proposedPath: String {
        ((parent?.segments ?? []) + [name.trimmingCharacters(in: .whitespacesAndNewlines)])
            .joined(separator: " › ")
    }

    private var isUnchanged: Bool {
        if case .rename(let path) = prompt { return name.trimmingCharacters(in: .whitespacesAndNewlines) == path.name }
        return false
    }

    private var scopeDescription: String {
        switch prompt {
        case .rename:
            "Renames this folder in \(affectedCount) recording names, including nested folders. Lesson numbers and titles are preserved."
        case .create:
            "Recordings added here use this folder path in their names and default export filenames."
        }
    }
}

private struct ProjectRenameContext: View {
    let path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("In folder").font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
            Label(path, systemImage: "folder").font(BlitzType.strong).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ProjectRenamePreview: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
            Text(value).font(BlitzType.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(BlitzUI.controlFill, in: .rect(cornerRadius: BlitzUI.controlRadius))
    }
}

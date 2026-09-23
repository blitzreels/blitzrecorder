import AVFoundation
import SwiftUI

struct BlitzReelsBrand: View {
    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: "BlitzReelsWordmarkWhite", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                Text("BlitzReels").font(.system(size: 18, weight: .bold))
            }
        }
        .accessibilityLabel("BlitzReels")
    }
}

struct BlitzReelsHandoffPanel: View {
    let project: RecordingProject
    let settings: RecordingSettings
    @Bindable var handoff = BlitzReelsHandoffController.shared
    @State private var selection: URL?

    private var files: [URL] { BlitzReelsExportFiles.files(project) }
    private var currentResult: URL? {
        handoff.projectID == project.id && handoff.selectedExportURL == selection ? handoff.createURL : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    BlitzReelsBrand().frame(width: 154, height: 24)
                    Text("Add captions and B-roll")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Send your exported MP4 and choose its captions in BlitzReels.")
                        .font(.system(size: 12)).foregroundStyle(BlitzUI.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let account = handoff.connection.account {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(account.user.email, systemImage: "checkmark.circle.fill")
                                .font(.system(size: 11)).foregroundStyle(BlitzUI.mint)
                                .lineLimit(2).textSelection(.enabled)
                            BlitzDropdown(configuration: .init(
                                title: "BlitzReels workspace",
                                selection: Binding(
                                    get: { handoff.connection.selectedWorkspaceID },
                                    set: { if let id = $0 { handoff.selectWorkspace(id) } }
                                ),
                                options: account.workspaces.map {
                                    BlitzDropdownOption(value: Optional($0.id), title: $0.name, detail: nil)
                                }
                            ))
                            .disabled(handoff.isWorking)
                            if account.workspaces.isEmpty {
                                Text("Create or join a workspace in BlitzReels to continue.")
                                    .font(.system(size: 12)).foregroundStyle(BlitzUI.secondaryText)
                            }
                        }
                    }
                    if files.isEmpty {
                        Label("Export an MP4 first.", systemImage: "film")
                            .font(.system(size: 13)).foregroundStyle(BlitzUI.secondaryText).padding(.vertical, 20)
                    } else {
                        ForEach(files, id: \.path) { url in
                            RecordingUploadChoice(
                                file: EditorAsset.output(url: url), isSelected: selection == url,
                                onSelect: { select(url) }
                            )
                            .disabled(handoff.isWorking)
                        }
                        Text("Sends this exported file. Later timeline changes need a new export.")
                            .font(.system(size: 11)).foregroundStyle(BlitzUI.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if handoff.isWorking {
                        if let progress = handoff.progress {
                            VStack(alignment: .leading, spacing: 8) {
                                ProgressView(value: progress).tint(BlitzUI.mint)
                                Text("\(Int(progress * 100))% uploaded").font(.system(size: 11)).monospacedDigit()
                            }
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                    if !handoff.status.isEmpty {
                        Text(handoff.status).font(.system(size: 12)).foregroundStyle(BlitzUI.secondaryText)
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                    if let url = handoff.upgradeURL {
                        Link("View BlitzReels plans", destination: url).blitzButton(.secondary)
                    }
                    if let url = handoff.setupURL {
                        Link("Finish account setup", destination: url).blitzButton(.secondary)
                    }
                }.padding(14)
            }
            Divider()
            VStack(spacing: 10) {
                if handoff.isWorking {
                    Button("Cancel") { handoff.cancel() }.blitzButton(.secondary)
                } else if handoff.connection.account == nil {
                    Button(handoff.connection.hasCredential ? "Reconnect to BlitzReels" : "Connect to BlitzReels") {
                        handoff.connect()
                    }.blitzButton(.accent)
                } else {
                    if let url = currentResult {
                        Link("Continue in BlitzReels", destination: url).blitzButton(.accent)
                    } else {
                        Button("Upload to BlitzReels", action: send)
                            .blitzButton(.accent)
                            .disabled(selection == nil || handoff.connection.selectedWorkspace == nil)
                    }
                    Text("Choose captions and optional B-roll next.")
                        .font(.system(size: 11)).foregroundStyle(BlitzUI.secondaryText)
                }
                if handoff.connection.hasCredential {
                    HStack {
                        Button("Disconnect") { handoff.disconnect() }
                            .blitzButton(.quiet).controlSize(.small).disabled(handoff.isWorking)
                        Link("Manage connection", destination: handoff.connection.client.origin.appendingPathComponent("dashboard/settings"))
                            .blitzButton(.quiet).controlSize(.small)
                    }
                }
            }.frame(maxWidth: .infinity).padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BlitzUI.projectLibraryBackground).foregroundStyle(BlitzUI.primaryText)
        .task(id: project.id) {
            let selected = handoff.projectID == project.id ? handoff.selectedExportURL : nil
            selection = selected.flatMap { files.contains($0) ? $0 : nil } ?? files.first
            await handoff.restoreConnection()
        }
        .onChange(of: handoff.selectedExportURL) { _, url in
            if handoff.projectID == project.id, let url, files.contains(url) { selection = url }
        }
        .onChange(of: files) { _, urls in
            if !urls.contains(where: { $0 == selection }) { selection = urls.first }
        }
    }

    private func select(_ url: URL) {
        selection = url
        handoff.selectExport(.init(fileURL: url, project: project, settings: settings))
    }

    private func send() {
        guard let selection else { return }
        handoff.send(.init(fileURL: selection, project: project, settings: settings))
    }
}

private struct RecordingUploadChoice: View {
    let file: EditorAsset
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var thumbnail: NSImage?
    @State private var metadata = ""

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                ZStack {
                    Rectangle().fill(.black)
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: file.systemImage).font(.system(size: 22)).foregroundStyle(
                            BlitzUI.secondaryText)
                    }
                }.frame(width: 72, height: 50).clipShape(.rect(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 5) {
                    Text(file.url.lastPathComponent)
                        .font(.system(size: 12, weight: .semibold)).lineLimit(2).truncationMode(.middle)
                    Text("Exported MP4")
                        .font(.system(size: 10)).foregroundStyle(BlitzUI.secondaryText)
                    Text(metadata).font(.system(size: 10, design: .monospaced)).foregroundStyle(BlitzUI.secondaryText)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18)).foregroundStyle(isSelected ? BlitzUI.mint : BlitzUI.secondaryText)
            }.padding(10)
        }.buttonStyle(BlitzSelectionButtonStyle(isSelected: isSelected)).accessibilityAddTraits(
            isSelected ? .isSelected : []
        )
        .task(id: file.id) {
            let asset = AVURLAsset(url: file.url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 320, height: 180)
            if let frame = try? await generator.image(at: .zero) {
                thumbnail = NSImage(cgImage: frame.image, size: .zero)
            }
            let duration = (try? await asset.load(.duration).seconds) ?? 0
            let size = (try? file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if duration.isFinite {
                metadata =
                    String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60)
                    + " · " + ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            }
        }
    }
}

import AVFoundation
import SwiftUI

struct BlitzReelsBrand: View {
    private static let onDark = BlitzReelsPitch.bundledImage("BlitzReelsWordmarkWhite")
    private static let onLight = BlitzReelsPitch.bundledImage("BlitzReelsWordmarkDark")

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let image = colorScheme == .dark ? Self.onDark : Self.onLight {
                image.resizable().aspectRatio(contentMode: .fit)
            } else {
                Text("BlitzReels").font(BlitzType.title)
            }
        }
        .accessibilityLabel("BlitzReels")
    }
}

struct BlitzReelsHandoffPanel: View {
    let project: RecordingProject
    let settings: RecordingSettings
    let offer: BlitzReelsPitch.Offer
    let openExport: () -> Void
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
                    Text(offer.headline)
                        .font(BlitzType.title)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(BlitzReelsPitch.summary)
                        .font(BlitzType.body).foregroundStyle(BlitzUI.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if handoff.connection.account == nil {
                        BlitzReelsOutcomeList(outcomes: offer.outcomes).padding(.top, 4)
                    }
                    if let account = handoff.connection.account {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(account.user.email, systemImage: "checkmark.circle.fill")
                                .font(BlitzType.caption).foregroundStyle(BlitzUI.accent)
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
                                    .font(BlitzType.body).foregroundStyle(BlitzUI.secondaryText)
                            }
                        }
                        exportChoices
                    }
                    if handoff.isWorking {
                        if let progress = handoff.progress {
                            VStack(alignment: .leading, spacing: 8) {
                                ProgressView(value: progress).tint(BlitzUI.accent)
                                Text("\(Int(progress * 100))% uploaded").font(BlitzType.caption).monospacedDigit()
                            }
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                    if !handoff.status.isEmpty {
                        Text(handoff.status).font(BlitzType.body).foregroundStyle(BlitzUI.secondaryText)
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                    if let url = handoff.upgradeURL {
                        Button("View BlitzReels plans") { NSWorkspace.shared.open(url) }.blitzButton(.secondary)
                    }
                    if let url = handoff.setupURL {
                        Button("Finish account setup") { NSWorkspace.shared.open(url) }.blitzButton(.secondary)
                    }
                }.padding(14)
            }
            Divider()
            VStack(spacing: 10) {
                if handoff.isWorking {
                    Button("Cancel") { handoff.cancel() }.blitzButton(.secondary)
                } else if handoff.connection.account == nil {
                    Button(handoff.connection.hasCredential ? "Reconnect to BlitzReels" : "Try BlitzReels free") {
                        handoff.connect()
                    }.blitzButton(.accent)
                    if !handoff.connection.hasCredential {
                        Text(BlitzReelsPitch.trialTerms)
                            .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    if let url = currentResult {
                        Button("Continue in BlitzReels") { NSWorkspace.shared.open(url) }.blitzButton(.accent)
                    } else {
                        Button("Upload to BlitzReels", action: send)
                            .blitzButton(.accent)
                            .disabled(selection == nil || handoff.connection.selectedWorkspace == nil)
                    }
                    Text("Choose captions and optional B-roll next.")
                        .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                }
                if handoff.connection.hasCredential {
                    HStack {
                        Button("Disconnect") { handoff.disconnect() }
                            .blitzButton(.quiet).controlSize(.small).disabled(handoff.isWorking)
                        Button("Manage connection") { NSWorkspace.shared.open(handoff.connection.client.origin.appendingPathComponent("dashboard/settings")) }
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

    @ViewBuilder private var exportChoices: some View {
        if files.isEmpty {
            Label("Export an MP4 first.", systemImage: "film")
                .font(BlitzType.callout).foregroundStyle(BlitzUI.secondaryText).padding(.top, 20)
            Button("Go to Export", systemImage: BlitzSymbols.export, action: openExport)
                .blitzButton(.secondary)
                .padding(.bottom, 20)
        } else {
            ForEach(files, id: \.path) { url in
                RecordingUploadChoice(
                    file: EditorAsset.output(url: url), isSelected: selection == url,
                    onSelect: { select(url) }
                )
                .disabled(handoff.isWorking)
            }
            Text("Sends this exported file. Later timeline changes need a new export.")
                .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
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
                        Image(systemName: file.systemImage).font(BlitzType.glyph(22)).foregroundStyle(
                            BlitzUI.secondaryText)
                    }
                }.frame(width: 72, height: 50).clipShape(.rect(cornerRadius: BlitzUI.controlRadius))
                VStack(alignment: .leading, spacing: 5) {
                    Text(file.url.lastPathComponent)
                        .font(BlitzType.strong).lineLimit(2).truncationMode(.middle)
                    Text("Exported MP4")
                        .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                    Text(metadata).font(BlitzType.caption.monospacedDigit()).foregroundStyle(BlitzUI.secondaryText)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(BlitzType.glyph(18)).foregroundStyle(isSelected ? BlitzUI.accent : BlitzUI.secondaryText)
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

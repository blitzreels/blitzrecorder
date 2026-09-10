import AVFoundation
import SwiftUI

struct BlitzReelsHandoffPanel: View {
    let project: RecordingProject
    let settings: RecordingSettings
    @Bindable var handoff = BlitzReelsHandoffController.shared
    @State private var selection: URL?

    private var files: [EditorAsset] {
        EditorAsset.assets(project: project, finalVideoURL: project.finalVideoPath.map(URL.init(fileURLWithPath:)))
            .filter { $0.isVideo && $0.exists }
    }
    private var currentResult: URL? { handoff.projectID == project.id ? handoff.createURL : nil }
    private var feedback: String {
        handoff.projectID == project.id || handoff.isWorking ? handoff.status : ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Choose the video you want to turn into clips.")
                        .font(.system(size: 12)).foregroundStyle(BlitzUI.secondaryText)
                    if handoff.hasKey {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(BlitzUI.mint)
                    }
                    ForEach(files) { file in
                        RecordingUploadChoice(
                            file: file, isSelected: selection == file.url, onSelect: { selection = file.url }
                        )
                        .disabled(handoff.isWorking)
                    }
                    if files.isEmpty {
                        Label("Export a video to send this recording.", systemImage: "film")
                            .font(.system(size: 13)).foregroundStyle(BlitzUI.secondaryText).padding(.vertical, 28)
                    } else {
                        Label(
                            "Source videos include recorded audio. Export again to include your latest edits.",
                            systemImage: "info.circle"
                        )
                        .font(.system(size: 11)).foregroundStyle(BlitzUI.secondaryText)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                    }
                    if let code = handoff.userCode {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Confirm this code in your browser").font(.system(size: 12, weight: .semibold))
                            Text(code).font(.system(size: 24, weight: .semibold, design: .monospaced)).textSelection(
                                .enabled)
                            Text("Sign in to connect your BlitzReels account.")
                                .font(.system(size: 11)).foregroundStyle(BlitzUI.secondaryText)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                            .background(BlitzUI.cardFill, in: .rect(cornerRadius: 12))
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
                    if !feedback.isEmpty {
                        Text(feedback).font(.system(size: 12)).foregroundStyle(BlitzUI.secondaryText)
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(14)
            }.frame(maxHeight: 430)
            Divider()
            VStack(spacing: 10) {
                if handoff.isWorking {
                    Button("Cancel upload") { handoff.cancel() }
                } else if let url = currentResult {
                    Link("Open in BlitzReels", destination: url)
                        .buttonStyle(BlitzButtonStyle(.accent))
                    Button("Send selected", action: send).disabled(selection == nil)
                } else {
                    Button(handoff.hasKey ? "Send recording" : "Connect and send", action: send)
                        .buttonStyle(BlitzButtonStyle(.accent)).disabled(selection == nil)
                }
                if handoff.hasKey {
                    Button("Disconnect") { handoff.disconnect() }.disabled(handoff.isWorking)
                }
            }.frame(maxWidth: .infinity).padding(14)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(BlitzUI.projectLibraryBackground).foregroundStyle(BlitzUI.primaryText)
            .buttonStyle(BlitzButtonStyle(.secondary))
            .onAppear { selection = files.first?.url }
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
                    Text(file.kind == .output ? "Finished export" : "\(file.title) + audio")
                        .font(.system(size: 12, weight: .semibold))
                    Text(file.kind == .output ? "Your last rendered video" : "Original source · without timeline edits")
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

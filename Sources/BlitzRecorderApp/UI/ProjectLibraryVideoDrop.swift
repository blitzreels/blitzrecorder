import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Videos dragged in from Finder become projects. Only file drags target it, so moving recordings between
/// folders inside the library never shows the import overlay.
struct ProjectLibraryVideoDrop: ViewModifier {
    @Bindable var vm: RecorderViewModel
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                guard vm.canImportVideos, vm.libraryActions.videoImportTask == nil else { return false }
                Task {
                    var urls: [URL] = []
                    for provider in providers {
                        if let url = await provider.loadFileURL() { urls.append(url) }
                    }
                    _ = vm.importVideos(urls)
                }
                return true
            }
            .overlay {
                if isTargeted {
                    ProjectLibraryDropOverlay(canImport: vm.canImportVideos)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: isTargeted)
    }
}

private struct ProjectLibraryDropOverlay: View {
    let canImport: Bool

    var body: some View {
        ZStack {
            Rectangle().fill(BlitzUI.overlayFill.opacity(0.6))
            VStack(spacing: 10) {
                BlitzSymbol(configuration: .init(name: BlitzSymbols.saveToMac, size: 30))
                    .foregroundStyle(canImport ? BlitzUI.accent : BlitzUI.secondaryText)
                Text(canImport ? "Drop to import" : "Wait for the current import to finish")
                    .font(BlitzType.headline)
                    .foregroundStyle(BlitzUI.primaryText)
                Text("MP4, MOV, or M4V. Edited where it is, never copied.")
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.secondaryText)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .blitzGlass(cornerRadius: BlitzUI.cardRadius)
            .shadow(color: BlitzUI.elevationShadow, radius: 18, y: 6)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The row a video takes in the list while it imports, so a drop shows up where the project will land.
struct ProjectLibraryImportRow: View {
    let progress: VideoProjectImporter.Progress
    let cancel: () -> Void

    private typealias Layout = ProjectLibrarySidebarLayout

    private var detail: String {
        guard let fraction = progress.fraction else { return progress.stage }
        return "\(progress.stage) · \(Int((fraction * 100).rounded()))%"
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: Layout.thumbnailRadius, style: .continuous)
                    .fill(BlitzUI.controlFill)
                ProgressView().controlSize(.small)
            }
            .frame(width: Layout.thumbnailSize.width, height: Layout.thumbnailSize.height)
            VStack(alignment: .leading, spacing: 5) {
                Text((progress.filename as NSString).deletingPathExtension)
                    .font(BlitzType.navigation)
                    .foregroundStyle(BlitzUI.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                ProgressView(value: progress.fraction)
                    .progressViewStyle(.linear)
                    .tint(BlitzUI.accent)
                    .controlSize(.mini)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: cancel) { Image(systemName: "xmark") }
                .blitzButton(.quiet)
                .accessibilityLabel("Cancel import")
                .help("Cancel import")
        }
        .padding(Layout.rowPadding)
        .frame(minHeight: Layout.thumbnailSize.height + Layout.rowPadding * 2)
        .background(BlitzUI.quietFill, in: .rect(cornerRadius: Layout.rowRadius, style: .continuous))
        .listRowInsets(Layout.rowInsets)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Importing \(progress.filename), \(detail)")
    }
}

extension View {
    func projectLibraryVideoDrop(_ vm: RecorderViewModel) -> some View {
        modifier(ProjectLibraryVideoDrop(vm: vm))
    }
}

private extension NSItemProvider {
    func loadFileURL() async -> URL? {
        await withCheckedContinuation { continuation in
            _ = loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                continuation.resume(returning: data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) })
            }
        }
    }
}

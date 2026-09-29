import AppKit
import SwiftUI

extension ProjectLibraryView {
    private struct MediaWaveformRequest {
        let values: [Float]
        let tint: Color
    }

    @ViewBuilder
    func projectMedia(
        _ project: RecordingProjectHistory.Entry
    ) -> some View {
        let captureAssets = mediaAssets.filter { $0.kind != .output }
        let outputAssets = mediaAssets.filter { $0.kind == .output }
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Files").font(BlitzType.section).foregroundStyle(BlitzUI.primaryText)
                    Text(mediaCaptureSummary(captureAssets))
                        .font(BlitzType.caption)
                        .foregroundStyle(BlitzUI.secondaryText)
                }

                Spacer(minLength: 12)

                Button {
                    vm.revealProject(project)
                } label: {
                    Label("Show in Finder", systemImage: "folder.fill")
                }
                .blitzButton(.secondary)
                .controlSize(.small)
            }

            if isLoadingMediaAssets, mediaAssetsProjectID != project.id {
                ProgressView("Loading media…")
                    .font(BlitzType.body)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if captureAssets.isEmpty {
                Text("No original capture files are available for this recording.")
                    .font(BlitzType.body)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .padding(.vertical, 24)
            } else {
                mediaAssetList(.init(title: "Original captures", assets: captureAssets))
            }

            if !outputAssets.isEmpty {
                mediaAssetList(.init(title: "Exports", assets: outputAssets))
            }
        }
    }

    private struct MediaAssetListConfiguration {
        let title: String
        let assets: [EditorAsset]
    }

    private func mediaAssetList(_ configuration: MediaAssetListConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(configuration.title)
                .font(BlitzType.strong)
                .foregroundStyle(BlitzUI.primaryText)
                .padding(.bottom, 4)

            ForEach(configuration.assets) { asset in
                mediaAssetRow(asset)

                if asset.id != configuration.assets.last?.id {
                    Rectangle()
                        .fill(BlitzUI.separator)
                        .frame(height: 1)
                }
            }
        }
    }

    private func mediaAssetRow(_ asset: EditorAsset) -> some View {
        let details = projectWaveformLibrary.technicalMetadata[asset.id]
        let duration = projectWaveformLibrary.durations[asset.id]
            .map(ProjectLibraryMetadata.durationLabel) ?? "—"
        let fileSize = projectWaveformLibrary.fileSizes[asset.id] ?? "—"
        let format = details?.format ?? asset.url.pathExtension.uppercased()
        return HStack(spacing: 16) {
            mediaAssetVisual(asset)
                .frame(width: 144, height: 81)
                .background(BlitzUI.quietFill, in: .rect(cornerRadius: BlitzUI.controlRadius))
                .clipShape(.rect(cornerRadius: BlitzUI.controlRadius))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(mediaAssetTitle(asset))
                        .font(BlitzType.strong)
                        .foregroundStyle(BlitzUI.primaryText)

                    if projectWaveformLibrary.loadingIDs.contains(asset.id)
                        || projectWaveformLibrary.filmstripLoadingCounts[asset.id] != nil {
                        ProgressView().controlSize(.mini)
                            .help(asset.isAudio ? "Preparing waveform" : "Preparing media previews")
                    }
                    if !asset.exists {
                        Text("Missing file")
                            .font(BlitzType.caption)
                            .foregroundStyle(BlitzUI.warning)
                    }

                    Spacer(minLength: 8)

                    Text(duration)
                        .font(BlitzType.caption.monospaced())
                        .foregroundStyle(BlitzUI.secondaryText)
                }

                if let details {
                    Text(details.quality)
                        .font(BlitzType.caption)
                        .foregroundStyle(BlitzUI.secondaryText)
                        .lineLimit(2)
                }

                Text("\(format) · \(fileSize) · \(asset.url.lastPathComponent)")
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(asset.url.lastPathComponent)
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([asset.url])
            } label: {
                BlitzSymbol(configuration: .init(name: "folder", size: 16))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(BlitzSelectionButtonStyle(isSelected: false))
            .disabled(!asset.exists)
            .pointingHandCursor(enabled: asset.exists)
            .accessibilityLabel("Show \(mediaAssetTitle(asset)) in Finder")
            .help("Show \(asset.url.lastPathComponent) in Finder")
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func mediaAssetVisual(_ asset: EditorAsset) -> some View {
        if asset.isVideo, let frame = projectWaveformLibrary.filmstrips[asset.id]?.first {
            Image(decorative: frame, scale: 1)
                .resizable()
                .scaledToFit()
        } else if asset.isAudio, asset.exists {
            mediaWaveform(MediaWaveformRequest(
                values: projectWaveformLibrary.waveforms[asset.id] ?? [],
                tint: BlitzUI.secondaryText
            ))
            .padding(.horizontal, 12)
            .padding(.vertical, 22)
        } else {
            BlitzSymbol(configuration: .init(name: asset.systemImage, size: 24))
                .foregroundStyle(BlitzUI.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func mediaWaveform(
        _ request: MediaWaveformRequest
    ) -> some View {
        if request.values.isEmpty {
            BlitzSymbol(configuration: .init(name: "waveform", size: 24))
                .foregroundStyle(request.tint.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Canvas { context, size in
                let slot = size.width / CGFloat(request.values.count)
                let barWidth = max(1, slot - 1)
                let maximumHeight = size.height - 8
                for (index, value) in request.values.enumerated() {
                    let height = max(1.5, CGFloat(value) * maximumHeight)
                    let bar = CGRect(
                        x: CGFloat(index) * slot + (slot - barWidth) / 2,
                        y: (size.height - height) / 2,
                        width: barWidth,
                        height: height
                    )
                    context.fill(
                        Path(roundedRect: bar, cornerRadius: barWidth / 2),
                        with: .color(request.tint.opacity(0.84))
                    )
                }
            }
        }
    }

    private func mediaCaptureSummary(
        _ assets: [EditorAsset]
    ) -> String {
        let screenCount = assets.filter { $0.kind == .screen && $0.exists }.count
        let cameraCount = assets.filter { $0.kind == .camera && $0.exists }.count
        let audioCount = assets.filter {
            ($0.kind == .microphone || $0.kind == .systemAudio) && $0.exists
        }.count
        return ProjectMediaInventorySummary(
            screenCaptureCount: screenCount,
            cameraCaptureCount: cameraCount,
            audioTrackCount: audioCount
        ).label
    }

    private func mediaAssetTitle(
        _ asset: EditorAsset
    ) -> String {
        let baseTitle: String
        switch asset.kind {
        case .output: baseTitle = "Finished export"
        case .screen: baseTitle = "Screen capture"
        case .camera: baseTitle = "Camera capture"
        case .microphone: baseTitle = "Microphone"
        case .systemAudio: baseTitle = "Mac audio"
        case .other: baseTitle = asset.title
        }
        let matchingAssets = mediaAssets.filter { $0.kind == asset.kind }
        guard matchingAssets.count > 1,
              let index = matchingAssets.firstIndex(where: { $0.id == asset.id }) else {
            return baseTitle
        }
        return "\(baseTitle) \(index + 1)"
    }

}

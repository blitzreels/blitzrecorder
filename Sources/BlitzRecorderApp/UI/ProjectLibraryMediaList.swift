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
            BlitzAdaptiveRow() {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Files").font(BlitzType.section).foregroundStyle(BlitzUI.primaryText)
                    Text(mediaCaptureSummary(captureAssets))
                        .font(BlitzType.caption)
                        .foregroundStyle(BlitzUI.secondaryText)
                }


                Button {
                    vm.revealProject(project)
                } label: {
                    Label("Show in Finder", systemImage: BlitzSymbols.folder)
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
        VStack(alignment: .leading, spacing: 10) {
            Text(configuration.title)
                .font(BlitzType.strong)
                .foregroundStyle(BlitzUI.primaryText)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 172, maximum: 260), spacing: 14, alignment: .top)],
                      alignment: .leading, spacing: 16) {
                ForEach(configuration.assets) { asset in
                    mediaAssetTile(asset)
                }
            }
        }
    }

    /// One capture: its picture or waveform, a name, and one line of facts. Click to show it in Finder.
    private func mediaAssetTile(_ asset: EditorAsset) -> some View {
        let details = projectWaveformLibrary.technicalMetadata[asset.id]
        let duration = projectWaveformLibrary.durations[asset.id].map(ProjectLibraryMetadata.durationLabel)
        let fileSize = projectWaveformLibrary.fileSizes[asset.id]
        let format = details?.format ?? asset.url.pathExtension.uppercased()
        let isLoading = projectWaveformLibrary.loadingIDs.contains(asset.id)
            || projectWaveformLibrary.filmstripLoadingCounts[asset.id] != nil
        let facts = [duration, details?.quality.components(separatedBy: " · ").first, fileSize].compactMap { $0 }
        return Button {
            NSWorkspace.shared.activateFileViewerSelecting([asset.url])
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                mediaAssetVisual(asset)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .background(BlitzUI.controlFill)
                    .clipShape(.rect(cornerRadius: BlitzUI.cardRadius, style: .continuous))
                    .overlay { BlitzEdgeHighlight(cornerRadius: BlitzUI.cardRadius) }
                    .overlay(alignment: .topTrailing) {
                        if isLoading {
                            ProgressView().controlSize(.mini).padding(8)
                        }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(mediaAssetTitle(asset))
                            .font(BlitzType.label)
                            .foregroundStyle(BlitzUI.primaryText)
                            .lineLimit(1)
                        if !asset.exists {
                            Text("Missing")
                                .font(BlitzType.caption)
                                .foregroundStyle(BlitzUI.warning)
                        }
                    }
                    Text(facts.isEmpty ? format : facts.joined(separator: " · "))
                        .font(BlitzType.caption)
                        .foregroundStyle(BlitzUI.secondaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .padding(.horizontal, 2)
            }
            .contentShape(.rect)
        }
        .buttonStyle(BlitzPressButtonStyle())
        .disabled(!asset.exists)
        .help([details?.quality, "\(format) · \(asset.url.lastPathComponent)", "Click to show in Finder"]
            .compactMap { $0 }.joined(separator: "\n"))
        .accessibilityLabel("\(mediaAssetTitle(asset)), show in Finder")
    }

    @ViewBuilder
    private func mediaAssetVisual(_ asset: EditorAsset) -> some View {
        if asset.isVideo, let frame = projectWaveformLibrary.posters[asset.id] {
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

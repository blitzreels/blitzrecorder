import SwiftUI

extension EditorTimelineView {
    var header: some View {
        Group {
            if headerWidth >= Self.singleRowHeaderWidth {
                HStack(spacing: 16) {
                    editActions
                    Spacer(minLength: 0)
                    listeningAndZoomControls
                        .frame(maxWidth: max(0, (headerWidth - transportWidth) / 2 - 48), alignment: .trailing)
                }
                .overlay {
                    playbackControls
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { transportWidth = $0 }
                }
                .blitzWorkspaceToolbar()
            } else {
                VStack(spacing: 0) {
                    HStack {
                        editActions
                        Spacer(minLength: 0)
                        listeningAndZoomControls.fixedSize()
                    }
                    .blitzWorkspaceToolbar()
                    playbackControls
                        .frame(maxWidth: .infinity)
                        .blitzWorkspaceToolbar()
                }
            }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { headerWidth = $0 }
    }

    private static let singleRowHeaderWidth: CGFloat = 1_120

    private var editActions: some View {
        HStack(spacing: 6) {
            Button(action: onSplit) { Label("Split", systemImage: "scissors") }
                .blitzButton(.secondary)
                .disabled(!isInteractive || !canSplitSelection)
                .help(selectedPlacedItem == nil ? "Split the clip at the playhead. All sources stay linked (⌘B)."
                      : "Split the selected item at the playhead (⌘B).")
            Button(action: onDeleteSelection) {
                Label(deleteAction == .toggleAsset ? "Hide" : "Delete",
                      systemImage: deleteAction == .toggleAsset ? "eye.slash.fill" : "trash.fill")
            }
                .blitzButton(.secondary)
                .disabled(!isInteractive || deleteAction == nil)
                .help(deleteAction.map(EditorDeleteRouting.help) ?? "Drag to select a range, then press Return or Delete.")
            BlitzGlassMenu(entries: selectionEntries, menuWidth: 280) {
                HStack(spacing: 6) {
                    Image(systemName: "selection.pin.in.out").font(BlitzType.glyph(12))
                    Text("Range").font(BlitzType.label)
                    BlitzMenuChevron()
                }
                .foregroundStyle(BlitzUI.primaryText)
                .padding(.horizontal, 10)
                .frame(height: BlitzControlMetrics.height(.small))
            }
            .accessibilityLabel("Range actions")
            .help("Mark, restore, or classify a time range")
        }
        .controlSize(.small)
        .fixedSize(horizontal: true, vertical: false)
    }

    var selectionStatus: some View {
        HStack(spacing: 10) {
            if let selected = selection?.rangeSelection {
                Text("\(rangeTime(projection.displayTime(selected.bounds.start))) – \(rangeTime(projection.displayTime(selected.bounds.end)))")
                    .foregroundStyle(BlitzUI.primaryText)
                Text(String(format: "%.2f s selected", selected.displayRanges.reduce(0) {
                    $0 + projection.displayTime($1.end) - projection.displayTime($1.start)
                }))
                Text("Return to delete")
                Button { selection = nil } label: { Image(systemName: "xmark") }
                    .blitzButton(.quiet)
                    .controlSize(.mini)
                    .accessibilityLabel("Clear selection")
                    .help("Clear selection (Esc)")
            } else if case .asset(let id) = selection, let asset = assets.first(where: { $0.id == id }) {
                Text("\(asset.title) selected · Delete to \(asset.isVideo ? "hide" : "mute") the entire track")
            } else if selection != nil {
                Text("Item selected · Return to delete · Esc to clear")
            } else {
                Text("Drag to select · Return to delete · ⌘Z to undo")
            }
            Spacer(minLength: 0)
            Text("\(clipLayout.clips.count) clips")
        }
        .font(BlitzType.caption)
        .monospacedDigit()
        .foregroundStyle(BlitzUI.secondaryText)
        .lineLimit(1)
        .padding(.horizontal, 18)
        .frame(height: 30)
        .overlay(alignment: .top) { Rectangle().fill(BlitzUI.separator).frame(height: 1) }
    }

    @ViewBuilder
    var selectionCommands: some View {
        ForEach(Array(selectionEntries.enumerated()), id: \.offset) { _, entry in
            switch entry {
            case .item(let item):
                Button(item.title, systemImage: item.systemImage ?? "circle", action: item.action)
                    .disabled(!item.isEnabled)
            case .divider: Divider()
            case .section(let title): Text(title)
            }
        }
    }

    private var selectionEntries: [BlitzMenuEntry] {
        var entries: [BlitzMenuEntry] = [
            .item(.init(title: "Mark range start", subtitle: "I", systemImage: "selection.pin.in.out",
                        isEnabled: isInteractive, action: onMarkIn)),
            .item(.init(title: "Mark range end", subtitle: "O", systemImage: "selection.pin.in.out",
                        isEnabled: isInteractive, action: onMarkOut))
        ]
        if let selected = selection?.rangeSelection {
            let canRestore = project?.edits.enabledCuts.contains { cut in
                selected.ranges.contains { $0.start < cut.end && $0.end > cut.start }
            } ?? false
            entries += [
                .divider,
                .item(.init(title: "Zoom to selection", systemImage: "viewfinder", action: {
                    let range = selected.bounds
                    let width = projection.displayTime(range.end) - projection.displayTime(range.start)
                    selectionFocusTime = (range.start + range.end) / 2
                    zoomLevel = EditorTimelineZoom.clamp(.init(
                        value: projection.duration / max(1, width * 2), duration: projection.duration
                    ))
                })),
                .item(.init(title: "Restore footage in selection", subtitle: "Shift Delete",
                            systemImage: "arrow.uturn.backward", isEnabled: isInteractive && canRestore,
                            action: onRestoreRange)),
                .item(.init(title: "Keep as speech", systemImage: "waveform",
                            isEnabled: isInteractive && silence.canClassify,
                            action: { classifySelectedRanges(.sound) })),
                .item(.init(title: "Mark as silence", systemImage: "waveform.slash",
                            isEnabled: isInteractive && silence.canClassify,
                            action: { classifySelectedRanges(.silence) }))
            ]
        }
        entries.append(.item(.init(title: "Clear selection", subtitle: "Esc", systemImage: "xmark",
                                  isEnabled: selection != nil, action: { selection = nil })))
        return entries
    }

    private var playbackControls: some View {
        EditorPlaybackControls(configuration: .init(
            time: projection.displayTime(playback.currentTime),
            liveTime: { [playback, projection] in projection.displayTime(playback.displayTime()) },
            duration: projection.duration,
            isPlaying: playback.isPlaying,
            isEnabled: isInteractive,
            rate: playback.playbackRate,
            onSeek: { seekAndSettle(to: projection.takeTime($0)) },
            onTogglePlayback: onTogglePlayback,
            onRateChange: onPlaybackRateChange
        ))
        .fixedSize()
    }

    private var listeningAndZoomControls: some View {
        HStack(spacing: 12) {
            BlitzPlaybackVolumeControl(configuration: .init(
                volume: Binding(get: { playback.playbackVolume }, set: { playback.setPlaybackVolume($0) }),
                sliderWidth: 64...140, onToggleMute: { playback.togglePlaybackMute() }
            ))
            .disabled(!isInteractive || playback.muteableSources.isEmpty)
            Rectangle().fill(BlitzUI.separator).frame(width: 1, height: 18).accessibilityHidden(true)
            HStack(spacing: 2) {
                zoomButton(.init(symbol: "minus.magnifyingglass", title: "Zoom out", help: "Zoom out (⌘−)", factor: 1 / 1.5))
                Slider(
                    value: logarithmicZoom,
                    in: log2(EditorTimelineZoom.minimum)...log2(EditorTimelineZoom.maximum(for: projection.duration))
                )
                    .controlSize(.small)
                    .tint(BlitzUI.mint)
                    .frame(minWidth: 88, idealWidth: 88, maxWidth: 200)
                    .accessibilityLabel("Timeline zoom")
                    .accessibilityValue(String(format: "%.2f×", zoomLevel))
                    .help("Timeline zoom (⌘− / ⌘+). Fit with F.")
                zoomButton(.init(symbol: "plus.magnifyingglass", title: "Zoom in", help: "Zoom in (⌘+)", factor: 1.5))
            }
            Button { zoomLevel = 1 } label: { Label("Fit", systemImage: "arrow.left.and.right") }
                .blitzButton(.secondary)
                .controlSize(.small)
                .disabled(zoomLevel == 1)
                .help("Fit the full recording in the timeline (F)")
            Button { showsShortcuts = true } label: {
                Image(systemName: "keyboard").font(BlitzType.glyph(13)).frame(width: 16)
            }
                .blitzButton(.quiet)
                .controlSize(.small)
                .accessibilityLabel("Keyboard shortcuts")
                .help("Keyboard shortcuts (?)")
        }
    }

    private struct ZoomStep {
        let symbol: String
        let title: String
        let help: String
        let factor: Double
    }

    private func zoomButton(_ step: ZoomStep) -> some View {
        Button {
            zoomLevel = EditorTimelineZoom.stepped(.init(value: zoomLevel, duration: projection.duration), factor: step.factor)
        } label: {
            Image(systemName: step.symbol).font(BlitzType.glyph(13)).frame(width: 16, height: 16)
        }
        .blitzButton(.quiet)
        .controlSize(.small)
        .accessibilityLabel(step.title)
        .help(step.help)
    }

    private var logarithmicZoom: Binding<Double> {
        Binding(
            get: { EditorTimelineZoom.sliderValue(.init(value: zoomLevel, duration: projection.duration)) },
            set: { zoomLevel = EditorTimelineZoom.scale(.init(value: $0, duration: projection.duration)) }
        )
    }

    private func rangeTime(_ time: Double) -> String {
        let value = time.isFinite ? min(projection.duration, max(0, time)) : 0
        let label = MediaTimecode.label(.init(time: value, duration: projection.duration))
        return label + String(format: ".%02d", Int((value * 100).rounded(.down)) % 100)
    }
}

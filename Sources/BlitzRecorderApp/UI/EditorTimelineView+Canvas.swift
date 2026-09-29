import SwiftUI

extension EditorTimelineView {
    func timelineBody(viewportWidth: CGFloat) -> some View {
        let trackViewport = max(trackScrollWidth > 0 ? trackScrollWidth - 16 : viewportWidth - gutterWidth - 24, 40)
        let layoutDuration = clipTrim.lockedDisplayDuration
            ?? EditorTimelineZoom.fitDuration(
                anchor: zoomFitDuration, zoom: zoomLevel, current: projection.duration)
        let pxPerSecond = pixelsPerSecond(.init(trackViewport: trackViewport, duration: layoutDuration))
        let contentWidth = max(CGFloat(projection.duration) * pxPerSecond, trackViewport)
        let viewport = EditorTimelineViewport.resolve(.init(
            offset: scrollOffset,
            viewportWidth: trackViewport,
            contentWidth: contentWidth
        ))

        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                gutterHeading
                EditorTimelinePinnedRuler(configuration: .init(
                    scrollOffset: rulerScrollOffset,
                    viewportWidth: trackViewport + 16,
                    content: ruler(.init(pxPerSecond: pxPerSecond, width: contentWidth, viewport: viewport))
                    .frame(width: contentWidth, height: rulerHeight, alignment: .topLeading)
                    .coordinateSpace(name: timelineContentSpace)
                    .padding(.horizontal, 8)
                ))
            }
            .frame(height: rulerHeight)
            .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 8) {
                    gutterColumn

                    ScrollView(.horizontal) {
                        ZStack(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 6) {
                                if duration > 0 {
                                    EditorVideoClipStrip(configuration: .init(
                                        layout: clipLayout, viewport: viewport, pixelsPerSecond: pxPerSecond,
                                        width: contentWidth, height: clipRowHeight,
                                        edits: project?.edits ?? .empty, duration: duration,
                                        selectedRanges: selection?.rangeSelection?.ranges ?? [],
                                        hoveredRange: hoveredClipRange,
                                        trimOrigin: clipTrim.origin,
                                        onSelect: clickVideoClip,
                                        onHover: { hoveredClipRange = $0 },
                                        onBeginTrim: { origin in
                                            clipTrim.beginTrim(.init(origin: origin, displayDuration: projection.duration))
                                        },
                                        onTrim: previewClipTrim,
                                        onEndTrim: commitClipTrim,
                                        onCancelTrim: cancelTimelineDrag))
                                        .background {
                                            if let asset = overviewAsset {
                                                clipFilmstrip(.init(asset: asset, pxPerSecond: pxPerSecond,
                                                    contentWidth: contentWidth, viewport: viewport))
                                            }
                                        }
                                        .clipShape(.rect(cornerRadius: 4))
                                        .disabled(!isInteractive)
                                        .contextMenu { selectionCommands; Divider(); timelineContextMenu }
                                    transcriptTrack(.init(pixelsPerSecond: pxPerSecond, contentWidth: contentWidth, viewport: viewport))
                                    if showsChaptersTrack {
                                        chaptersTrack(pxPerSecond: pxPerSecond, contentWidth: contentWidth)
                                    }
                                    if showsSegmentsTrack {
                                        segmentsTrack(pxPerSecond: pxPerSecond, contentWidth: contentWidth)
                                    }
                                    ForEach(placedTracks) { track in
                                        placedTrack(.init(track: track, pixelsPerSecond: pxPerSecond,
                                                          contentWidth: contentWidth, viewport: viewport))
                                    }
                                    ForEach(trackAssets) { asset in
                                        assetTrack(.init(asset: asset, pxPerSecond: pxPerSecond, contentWidth: contentWidth, viewport: viewport))
                                    }
                                    if !showsSegmentsTrack && sourceAssets.isEmpty {
                                        emptyHint
                                    }
                                }
                            }
                            .contentShape(.rect)
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 5, coordinateSpace: .named(timelineContentSpace))
                                    .onChanged { value in
                                        guard !clipTrim.isActive, !isPlacedTrack(at: value.startLocation.y),
                                            let range = EditorTimeRange.resolve(.init(
                                                anchor: projection.takeTime(Double(value.startLocation.x / pxPerSecond)),
                                                head: projection.takeTime(Double(value.location.x / pxPerSecond)), duration: duration
                                            ))
                                        else { return }
                                        selection = .range(range)
                                    },
                                isEnabled: isInteractive
                            )

                            if duration > 0 {
                                EditorTimelineSilenceOverlay(configuration: .init(
                                    segments: selectableSilenceSegments, projection: projection,
                                    pixelsPerSecond: pxPerSecond, viewport: viewport, rows: silenceMarkedRows))
                                    .equatable()
                                    .frame(width: viewport.width, height: contentHeight)
                                    .offset(x: viewport.lowerBound)
                                linkedSegmentOverlay(pxPerSecond)
                                if let range = hoveredClipRange, clipTrim.origin == nil,
                                    selection?.rangeSelection?.ranges.contains(range) != true {
                                    hoverOverlay(.init(range: range, pxPerSecond: pxPerSecond))
                                }
                                if let selected = selection?.rangeSelection {
                                    if selected.ranges.count == 1 {
                                        rangeOverlay(.init(range: selected.bounds, pxPerSecond: pxPerSecond))
                                    } else {
                                        EditorTimelineSelectionCanvas(configuration: .init(
                                            ranges: selected.displayRanges, projection: projection, viewport: viewport,
                                            pixelsPerSecond: pxPerSecond, height: contentHeight, tint: selectionTint))
                                            .frame(width: viewport.width, height: contentHeight)
                                            .offset(x: viewport.lowerBound)
                                            .allowsHitTesting(false)
                                    }
                                }
                            }
                        }
                        .frame(width: contentWidth, alignment: .topLeading)
                        .background { EditorTimelineKeyboardFocus().allowsHitTesting(false) }
                        .coordinateSpace(name: timelineContentSpace)
                        .padding(.horizontal, 8)
                    }
                    .scrollPosition($scrollPosition)
                    .onChange(of: zoomLevel) { _, _ in
                        zoomFitDuration = projection.duration
                        scrollToFocus(.init(pixelsPerSecond: pxPerSecond, contentWidth: contentWidth, trackViewport: trackViewport))
                    }
                    .onChange(of: selectionFocusTime) { _, _ in
                        guard selectionFocusTime != nil else { return }
                        scrollToFocus(.init(pixelsPerSecond: pxPerSecond, contentWidth: contentWidth, trackViewport: trackViewport))
                    }
                    .onChange(of: projection.duration) { old, new in
                        zoomFitDuration = EditorTimelineZoom.anchoredFitDuration(
                            currentAnchor: zoomFitDuration, oldDuration: old, zoom: zoomLevel)
                        let fit = EditorTimelineZoom.fitDuration(
                            anchor: zoomFitDuration, zoom: zoomLevel, current: new)
                        let pps = pixelsPerSecond(.init(trackViewport: trackViewport, duration: fit))
                        let width = max(CGFloat(new) * pps, trackViewport)
                        let clamped = EditorTimelineScroll.clamped(
                            offset: rulerScrollOffset.value, contentWidth: width, viewportWidth: trackViewport)
                        if abs(clamped - rulerScrollOffset.value) > 0.5 {
                            scrollPosition.scrollTo(x: clamped)
                        }
                    }
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.contentOffset.x
                    } action: { _, offset in
                        rulerScrollOffset.value = offset
                        scrollOffset = floor(max(0, offset - 8) / 128) * 128
                    }
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.containerSize.width
                    } action: { _, width in
                        trackScrollWidth = width
                    }
                }
                .frame(height: contentHeight)
                .padding(.top, 6)
                .padding(.bottom, 14)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .overlayPreferenceValue(EditorTimelineControlKey.self) { controls in
            GeometryReader { geometry in
                if duration > 0 {
                    ZStack(alignment: .topLeading) {
                        EditorTimelineHoverLine(hover: rulerHover)
                            .frame(width: trackViewport + 16)
                            .clipped()
                            .padding(.leading, gutterWidth + 8)
                            .zIndex(0)
                        EditorTimelinePlayhead(configuration: .init(
                            projection: projection, scrollOffset: rulerScrollOffset, pixelsPerSecond: pxPerSecond,
                            playbackTime: playback.currentTime, liveTime: { playback.displayTime() },
                            isPlaying: playback.isPlaying,
                            isInteractive: isInteractive, rulerHeight: rulerHeight, viewportWidth: trackViewport + 16,
                            onSeek: onSeek, onSeekEnded: onSeekEnded))
                            .frame(width: trackViewport + 16)
                            .clipped()
                            .padding(.leading, gutterWidth + 8)
                            .zIndex(1)
                        EditorTimelineControlLayer(configuration: .init(
                            controls: controls, geometry: geometry,
                            viewport: CGRect(x: gutterWidth + 8, y: rulerHeight + 6,
                                width: trackViewport + 16, height: max(0, geometry.size.height - rulerHeight - 6))))
                            .disabled(!isInteractive)
                            .zIndex(2)
                    }
                }
            }
        }
        .onContinuousHover { phase in
            let location: CGPoint?
            switch phase {
            case .active(let point): location = point
            case .ended: location = nil
            }
            rulerHover.update(.init(
                location: location,
                ruler: CGRect(x: gutterWidth + 8, y: 0, width: trackViewport + 16, height: rulerHeight),
                isInteractive: isInteractive && duration > 0))
        }
        .onChange(of: isInteractive) { _, enabled in
            if !enabled { rulerHover.position = nil }
        }
        .onDisappear { rulerHover.position = nil }
    }

    private struct PixelScaleRequest {
        let trackViewport: CGFloat
        let duration: Double
    }

    private func pixelsPerSecond(_ request: PixelScaleRequest) -> CGFloat {
        request.trackViewport / CGFloat(max(request.duration, 0.5))
            * CGFloat(EditorTimelineZoom.clamp(.init(value: zoomLevel, duration: request.duration)))
    }

    private struct ScrollFocus {
        let pixelsPerSecond: CGFloat
        let contentWidth: CGFloat
        let trackViewport: CGFloat
    }

    private func scrollToFocus(_ focus: ScrollFocus) {
        scrollPosition.scrollTo(x: EditorTimelineScroll.centered(
            on: projection.displayTime(selectionFocusTime ?? playback.currentTime),
            pixelsPerSecond: focus.pixelsPerSecond,
            contentWidth: focus.contentWidth,
            viewportWidth: focus.trackViewport
        ))
    }

    private struct RangeOverlayRequest {
        let range: EditorTimeRange
        let pxPerSecond: CGFloat
    }

    private func linkedSegmentOverlay(_ pxPerSecond: CGFloat) -> some View {
        let top = segmentsTrackTop
        let height = max(0, contentHeight - top)
        return Canvas { context, _ in
            if let range = selectedSceneRange {
                let start = CGFloat(projection.displayTime(range.start)) * pxPerSecond
                let end = CGFloat(projection.displayTime(range.end)) * pxPerSecond
                let path = Path(CGRect(x: start, y: top, width: max(0, end - start), height: height))
                context.fill(path, with: .color(BlitzUI.mint.opacity(0.08)))
                context.stroke(path, with: .color(BlitzUI.mint), lineWidth: 1.5)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func hoverOverlay(_ request: RangeOverlayRequest) -> some View {
        let start = CGFloat(projection.displayTime(request.range.start)) * request.pxPerSecond
        let end = CGFloat(projection.displayTime(request.range.end)) * request.pxPerSecond
        let top: CGFloat = 0
        return Rectangle()
            .fill(BlitzUI.controlFill)
            .overlay { Rectangle().strokeBorder(BlitzUI.tertiaryText, style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
            .frame(width: max(1, end - start), height: max(0, contentHeight - top))
            .offset(x: start, y: top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func rangeOverlay(_ request: RangeOverlayRequest) -> some View {
        EditorTimelineRangeHighlight(configuration: .init(
            range: request.range, projection: projection, pixelsPerSecond: request.pxPerSecond,
            height: contentHeight, tint: selectionTint))
            .onDisappear { cancelTimelineDrag() }
    }

    func seek(toContentX x: CGFloat, pxPerSecond: CGFloat) {
        guard duration > 0, pxPerSecond > 0 else { return }
        onSeek(projection.takeTime(min(max(0, Double(x / pxPerSecond)), projection.duration)))
    }
}

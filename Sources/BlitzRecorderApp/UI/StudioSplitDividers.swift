import AppKit
import BlitzRecorderCore
import SwiftUI

enum ScreenSplitDividerGeometry {
    struct Drag {
        let startHeight: Double
        let translation: CGFloat
        let canvasHeight: CGFloat
    }

    static func height(_ drag: Drag) -> Double {
        guard drag.startHeight.isFinite, drag.translation.isFinite,
              drag.canvasHeight.isFinite, drag.canvasHeight > 0 else {
            return Double(SceneLayout.defaultScreenSplitHeight)
        }
        let proposed = drag.startHeight + Double(drag.translation / drag.canvasHeight)
        let clamped = Double(SceneLayout.clampedScreenSplitHeight(CGFloat(proposed)))
        let snapDistance = min(0.018, 6 / Double(drag.canvasHeight))
        return [0.5, 2.0 / 3.0, 0.75].first { abs($0 - clamped) <= snapDistance } ?? clamped
    }
}

enum SideSplitDividerGeometry {
    struct Drag {
        let startWidth: Double
        let translation: CGFloat
        let canvasWidth: CGFloat
        let cameraIsLeft: Bool
        let layout: CaptureLayout
    }

    static func width(_ drag: Drag) -> Double {
        guard drag.startWidth.isFinite, drag.translation.isFinite,
              drag.canvasWidth.isFinite, drag.canvasWidth > 0 else {
            return Double(SceneLayout.defaultSideBySideCameraWidth(for: drag.layout))
        }
        let delta = Double(drag.translation / drag.canvasWidth) * (drag.cameraIsLeft ? 1 : -1)
        let clamped = Double(SceneLayout.clampedSideBySideCameraWidth(CGFloat(drag.startWidth + delta)))
        let snapDistance = min(0.018, 6 / Double(drag.canvasWidth))
        let portrait = Double(SceneLayout.portraitCameraWidth(for: drag.layout))
        return [portrait, 0.5].first { abs($0 - clamped) <= snapDistance } ?? clamped
    }
}

struct SideSplitDividerOverlay: View {
    @Bindable var vm: RecorderViewModel
    @State private var dragOrigin: DragOrigin?
    @State private var isHovering = false

    private struct DragOrigin {
        let width: Double
        let canvasWidth: CGFloat
    }

    var body: some View {
        GeometryReader { proxy in
            if vm.showsSideSplitControl, vm.canEditScene,
               !vm.canvas.isScreenCropModeEnabled, !vm.canvas.isCameraCropModeEnabled,
               !vm.canvas.previewCanvasFrame.isEmpty {
                let canvas = vm.canvas.previewCanvasFrame
                let dividerX = vm.sideSplitCameraIsLeft ? vm.sideSplitCameraWidth : 1 - vm.sideSplitCameraWidth
                handle
                    .frame(width: 28, height: max(0, canvas.height - 2))
                    .contentShape(.rect)
                    .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                        .onChanged { value in
                            if dragOrigin == nil {
                                dragOrigin = DragOrigin(width: vm.sideSplitCameraWidth, canvasWidth: canvas.width)
                            }
                            guard let dragOrigin else { return }
                            vm.previewSideSplitCameraWidth(SideSplitDividerGeometry.width(.init(
                                startWidth: dragOrigin.width,
                                translation: value.translation.width,
                                canvasWidth: dragOrigin.canvasWidth,
                                cameraIsLeft: vm.sideSplitCameraIsLeft,
                                layout: vm.settings.layout
                            )))
                        }
                        .onEnded { _ in
                            guard dragOrigin != nil else { return }
                            vm.commitSideSplitPreview()
                            dragOrigin = nil
                        }
                    )
                    .onHover {
                        isHovering = $0
                        ($0 ? NSCursor.resizeLeftRight : NSCursor.arrow).set()
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Camera and screen divider")
                    .accessibilityValue("\(Int((vm.sideSplitCameraWidth * 100).rounded())) percent camera")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: vm.setSideSplitCameraWidth(vm.sideSplitCameraWidth + 0.05)
                        case .decrement: vm.setSideSplitCameraWidth(vm.sideSplitCameraWidth - 0.05)
                        @unknown default: break
                        }
                    }
                    .help("Drag to share space between camera and screen")
                    .position(
                        x: canvas.minX + canvas.width * dividerX,
                        y: proxy.size.height - canvas.midY
                    )
            }
        }
        .onChange(of: vm.selectedSceneID) { _, _ in cancelDrag() }
        .onDisappear { cancelDrag() }
    }

    private var handle: some View {
        SplitDividerHandle(configuration: .init(lineAxis: .vertical, isActive: isHovering || dragOrigin != nil))
    }

    private func cancelDrag() {
        dragOrigin = nil
        vm.cancelSideSplitPreview()
        if isHovering {
            isHovering = false
            NSCursor.arrow.set()
        }
    }
}

struct SplitDividerOverlay: View {
    @Bindable var vm: RecorderViewModel
    @State private var dragOrigin: DragOrigin?
    @State private var isHovering = false

    private struct DragOrigin {
        let height: Double
        let canvasHeight: CGFloat
    }

    var body: some View {
        GeometryReader { proxy in
            if vm.showsScreenSplitControl, vm.canEditScene,
               !vm.canvas.isScreenCropModeEnabled, !vm.canvas.isCameraCropModeEnabled,
               !vm.canvas.previewCanvasFrame.isEmpty {
                let canvas = vm.canvas.previewCanvasFrame
                handle
                    .frame(width: max(0, canvas.width - 2), height: 28)
                    .contentShape(.rect)
                    .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                        .onChanged { value in
                            if dragOrigin == nil {
                                dragOrigin = DragOrigin(height: vm.screenSplitHeight, canvasHeight: canvas.height)
                            }
                            guard let dragOrigin else { return }
                            vm.previewScreenSplitHeight(ScreenSplitDividerGeometry.height(.init(
                                startHeight: dragOrigin.height,
                                translation: value.translation.height,
                                canvasHeight: dragOrigin.canvasHeight
                            )))
                        }
                        .onEnded { _ in
                            guard dragOrigin != nil else { return }
                            vm.commitScreenSplitPreview()
                            dragOrigin = nil
                        }
                    )
                    .onHover {
                        isHovering = $0
                        ($0 ? NSCursor.resizeUpDown : NSCursor.arrow).set()
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Screen and camera divider")
                    .accessibilityValue("\(Int((vm.screenSplitHeight * 100).rounded())) percent screen")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: vm.setScreenSplitHeight(vm.screenSplitHeight + 0.05)
                        case .decrement: vm.setScreenSplitHeight(vm.screenSplitHeight - 0.05)
                        @unknown default: break
                        }
                    }
                    .help("Drag to share space between screen and camera")
                    .position(
                        x: canvas.midX,
                        y: proxy.size.height - canvas.maxY + canvas.height * vm.screenSplitHeight
                    )
            }
        }
        .onChange(of: vm.selectedSceneID) { _, _ in cancelDrag() }
        .onDisappear { cancelDrag() }
    }

    private var handle: some View {
        SplitDividerHandle(configuration: .init(lineAxis: .horizontal, isActive: isHovering || dragOrigin != nil))
    }

    private func cancelDrag() {
        dragOrigin = nil
        vm.cancelScreenSplitPreview()
        if isHovering {
            isHovering = false
            NSCursor.arrow.set()
        }
    }
}

private struct SplitDividerHandle: View {
    struct Configuration {
        let lineAxis: Axis
        let isActive: Bool
    }

    let configuration: Configuration

    private var isVertical: Bool { configuration.lineAxis == .vertical }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(BlitzUI.accent.opacity(configuration.isActive ? 0.8 : 0))
                .frame(width: isVertical ? 1 : nil, height: isVertical ? nil : 1)
            Capsule()
                .fill(.black.opacity(0.7))
                .frame(width: isVertical ? 18 : 46, height: isVertical ? 46 : 18)
                .overlay {
                    Capsule()
                        .fill(configuration.isActive ? BlitzUI.accent : BlitzUI.supportingText)
                        .frame(width: isVertical ? 3 : 24, height: isVertical ? 24 : 3)
                }
        }
    }
}

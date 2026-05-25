import SwiftUI

struct SourcesSidebar: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                videoSection

                sidebarDivider

                audioSection

                sidebarDivider

                sceneSection

                sidebarDivider

                canvasSection
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .frame(width: 280)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private var sceneSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            subHeader("Scenes", icon: "square.split.2x1")
            SceneLayoutControls(vm: vm)
        }
    }

    private var canvasSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            subHeader("Canvas", icon: "paintpalette")
            CanvasAppearanceControls(vm: vm)
                .disabled(!vm.canEditScene)
        }
    }

    private var sidebarDivider: some View {
        Divider()
            .background(.white.opacity(0.08))
    }

    private var videoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            subHeader("Video", icon: "rectangle.on.rectangle", addSources: inactiveVideoSources)

            VStack(spacing: 6) {
                if shownVideoOrder.isEmpty {
                    EmptySourceHint(title: "No video sources")
                }
                ForEach(shownVideoOrder, id: \.self) { kind in
                    videoRow(for: kind)
                        .draggable(kind.rawValue) {
                            videoRow(for: kind).opacity(0.85)
                        }
                        .dropDestination(for: String.self) { items, _ in
                            return handleDrop(items, onto: kind)
                        }
                }
            }
        }
    }

    private var shownVideoOrder: [SceneLayerKind] {
        SceneLayoutProjection.frontToBackOrder(for: vm.settings.sceneLayout)
            .filter { vm.isSourceConfigured(captureSource(for: $0)) }
    }

    private var inactiveVideoSources: [CaptureSource] {
        [.screen, .camera].filter { !vm.isSourceConfigured($0) }
    }

    @ViewBuilder
    private func videoRow(for kind: SceneLayerKind) -> some View {
        switch kind {
        case .screen:
            VideoSourceRow(source: .screen, title: "Screen", symbol: "rectangle.on.rectangle", vm: vm)
        case .camera:
            VideoSourceRow(source: .camera, title: "Camera", symbol: "video.fill", vm: vm)
        }
    }

    private func handleDrop(_ items: [String], onto target: SceneLayerKind) -> Bool {
        guard vm.canEditScene else { return false }
        guard let raw = items.first,
              let dropped = SceneLayerKind(rawValue: raw),
              dropped != target else { return false }

        guard let order = SceneLayoutProjection.reorderedBackToFrontOrder(
            moving: dropped,
            onto: target,
            in: vm.settings.sceneLayout
        ) else { return false }

        vm.setSceneLayerOrder(order)
        return true
    }

    private func captureSource(for kind: SceneLayerKind) -> CaptureSource {
        switch kind {
        case .screen:
            return .screen
        case .camera:
            return .camera
        }
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            subHeader("Audio", icon: "waveform", addSources: inactiveAudioSources)

            if shownAudioSources.isEmpty {
                EmptySourceHint(title: "No audio sources")
            }
            ForEach(shownAudioSources, id: \.self) { source in
                audioRow(for: source)
            }
        }
    }

    private var shownAudioSources: [CaptureSource] {
        [.microphone, .systemAudio].filter { vm.isSourceConfigured($0) }
    }

    private var inactiveAudioSources: [CaptureSource] {
        [.microphone, .systemAudio].filter { !vm.isSourceConfigured($0) }
    }

    @ViewBuilder
    private func audioRow(for source: CaptureSource) -> some View {
        switch source {
        case .microphone:
            AudioTrackRow(
                title: "Mic",
                subtitle: vm.selectedMicrophoneDisplayName,
                symbol: "mic.fill",
                source: .microphone,
                levels: vm.micLevels,
                gain: Binding(get: { vm.settings.microphoneGain }, set: { vm.setMicrophoneGain($0) }),
                vm: vm
            )
        case .systemAudio:
            AudioTrackRow(
                title: "System",
                subtitle: "Mac audio",
                symbol: "speaker.wave.2.fill",
                source: .systemAudio,
                levels: vm.sysLevels,
                gain: Binding(get: { vm.settings.systemAudioGain }, set: { vm.setSystemAudioGain($0) }),
                vm: vm
            )
        case .screen, .camera:
            EmptyView()
        }
    }

    private func subHeader(_ title: String, icon: String, addSources: [CaptureSource] = []) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(title.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.7)
            Spacer(minLength: 0)
            if !addSources.isEmpty {
                Menu {
                    ForEach(addSources, id: \.self) { source in
                        Button {
                            vm.toggleSource(source)
                        } label: {
                            Label(source.shortLabel, systemImage: source.symbolName)
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .menuStyle(.button)
                .buttonStyle(.glass)
                .controlSize(.small)
                .disabled(vm.state != .idle)
                .pointingHandCursor()
                .help("Add \(title.lowercased()) source")
            }
        }
        .foregroundStyle(.white.opacity(0.45))
        .padding(.horizontal, 2)
    }
}

private struct CanvasAppearanceControls: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(CanvasBackgroundStyle.allCases, id: \.self) { style in
                    backgroundButton(for: style)
                }
            }

            Divider()
                .background(.white.opacity(0.08))

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "inset.filled.rectangle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(vm.settings.canvasPadding > 0 ? 0.82 : 0.5))
                        .frame(width: 16)
                    Text("Padding")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                    Spacer(minLength: 0)
                    Text(paddingLabel)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                        .monospacedDigit()
                    Button {
                        vm.setCanvasPadding(0)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .disabled(vm.settings.canvasPadding < 0.001)
                    .pointingHandCursor()
                    .help("Reset canvas padding")
                }

                Slider(
                    value: Binding(
                        get: { Double(vm.settings.canvasPadding) },
                        set: { vm.setCanvasPadding(CGFloat($0)) }
                    ),
                    in: 0...0.12,
                    step: 0.01
                )
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.055), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var paddingLabel: String {
        guard vm.settings.canvasPadding >= 0.001 else { return "Off" }
        return "\(Int((vm.settings.canvasPadding * 100).rounded()))%"
    }

    private func backgroundButton(for style: CanvasBackgroundStyle) -> some View {
        let isSelected = vm.settings.canvasBackgroundStyle == style
        return Button {
            vm.setCanvasBackgroundStyle(style)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: style.swatchColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(.white.opacity(isSelected ? 0.74 : 0.16), lineWidth: isSelected ? 1.5 : 1)
                    )
                    .frame(height: 28)

                HStack(spacing: 4) {
                    Text(style.displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(isSelected ? 0.96 : 0.68))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color(red: 0.09, green: 1.0, blue: 0.65))
                    }
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .tint(isSelected ? Color(red: 0.09, green: 1.0, blue: 0.65).opacity(0.18) : .clear)
        .pointingHandCursor()
        .help("Use \(style.displayName) canvas background")
    }
}

private extension CanvasBackgroundStyle {
    var swatchColors: [Color] {
        switch self {
        case .black:
            return [.black, .black]
        case .graphite:
            return [
                Color(red: 0.04, green: 0.05, blue: 0.07),
                Color(red: 0.15, green: 0.17, blue: 0.21),
                Color(red: 0.34, green: 0.37, blue: 0.42),
                Color(red: 0.08, green: 0.09, blue: 0.11),
                Color(red: 0.52, green: 0.57, blue: 0.62)
            ]
        case .aurora:
            return [
                Color(red: 0.02, green: 0.07, blue: 0.10),
                Color(red: 0.12, green: 0.10, blue: 0.30),
                Color(red: 0.25, green: 0.16, blue: 0.48),
                Color(red: 0.04, green: 0.40, blue: 0.36),
                Color(red: 0.18, green: 0.82, blue: 0.65),
                Color(red: 0.03, green: 0.13, blue: 0.16)
            ]
        case .ocean:
            return [
                Color(red: 0.01, green: 0.06, blue: 0.14),
                Color(red: 0.02, green: 0.16, blue: 0.30),
                Color(red: 0.04, green: 0.38, blue: 0.56),
                Color(red: 0.08, green: 0.62, blue: 0.74),
                Color(red: 0.02, green: 0.08, blue: 0.18)
            ]
        case .sunset:
            return [
                Color(red: 0.08, green: 0.04, blue: 0.12),
                Color(red: 0.28, green: 0.08, blue: 0.18),
                Color(red: 0.68, green: 0.18, blue: 0.25),
                Color(red: 0.94, green: 0.42, blue: 0.22),
                Color(red: 0.98, green: 0.66, blue: 0.30),
                Color(red: 0.06, green: 0.05, blue: 0.14)
            ]
        case .silver:
            return [
                Color(red: 0.30, green: 0.35, blue: 0.42),
                Color(red: 0.68, green: 0.72, blue: 0.78),
                Color(red: 0.92, green: 0.94, blue: 0.96),
                Color(red: 0.50, green: 0.57, blue: 0.66),
                Color(red: 0.98, green: 0.99, blue: 1.0)
            ]
        }
    }
}

private struct TransparentWebcamToggle: View {
    @Bindable var vm: RecorderViewModel
    let enabled: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.square")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(iconOpacity))
                .frame(width: 18, height: 18)

            Text("Transparent webcam")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(textOpacity))
                .lineLimit(1)

            Spacer(minLength: 0)

            Toggle("", isOn: Binding(
                get: { vm.settings.removesCameraBackgroundAfterRecording },
                set: { vm.setCameraBackgroundRemovalAfterRecording($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .contentShape(.rect(cornerRadius: 10))
        .disabled(vm.state != .idle || !enabled)
        .opacity(enabled ? 1 : 0.52)
        .onTapGesture {
            guard vm.state == .idle, enabled else { return }
            vm.setCameraBackgroundRemovalAfterRecording(!vm.settings.removesCameraBackgroundAfterRecording)
        }
        .pointingHandCursor()
        .help("Remove webcam background after recording")
    }

    private var iconOpacity: Double {
        guard enabled else { return 0.28 }
        return vm.settings.removesCameraBackgroundAfterRecording ? 0.82 : 0.45
    }

    private var textOpacity: Double {
        guard enabled else { return 0.3 }
        return vm.settings.removesCameraBackgroundAfterRecording ? 0.92 : 0.58
    }
}

private struct WebcamSourceMenu: View {
    @Bindable var vm: RecorderViewModel
    let enabled: Bool

    private var selectedName: String {
        if vm.isRemoteCameraSelected {
            return vm.selectedRemoteCameraName ?? "Remote iPhone"
        }
        if let selectedCameraID = vm.settings.selectedCameraID,
           let option = vm.localCameraOptions.first(where: { $0.id == selectedCameraID }) {
            return option.name
        }
        return "Default camera"
    }

    var body: some View {
        Menu {
            Button {
                vm.setCamera(nil)
            } label: {
                Label("Default camera", systemImage: vm.settings.selectedCameraID == nil ? "checkmark" : "video")
            }

            if !vm.localCameraOptions.isEmpty {
                Divider()
            }

            ForEach(vm.localCameraOptions, id: \.id) { option in
                Button {
                    vm.setCamera(option.id)
                } label: {
                    Label(option.name, systemImage: vm.settings.selectedCameraID == option.id ? "checkmark" : "video")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selectedName)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(enabled ? 0.42 : 0.24))
            }
            .foregroundStyle(.white.opacity(enabled ? 0.58 : 0.3))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect(cornerRadius: 7))
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .controlSize(.small)
        .disabled(vm.state != .idle)
        .pointingHandCursor()
        .help("Choose webcam source")
    }
}

private struct SceneLayoutControls: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
            spacing: 8
        ) {
            if vm.settings.selectedScenePreset == nil {
                sceneCell(
                    title: "Custom",
                    layout: vm.settings.sceneLayout,
                    isSelected: true
                ) {}
            }
            ForEach(supportedPresets, id: \.self) { preset in
                sceneCell(
                    title: preset.rawValue,
                    layout: SceneLayout.presetLayout(preset, for: vm.settings.layout),
                    isSelected: vm.settings.selectedScenePreset == preset
                ) {
                    vm.setScenePreset(preset)
                }
            }
        }
    }

    private var supportedPresets: [ScenePreset] {
        ScenePreset.allCases.filter { $0.supports(vm.settings.layout) }
    }

    private func sceneCell(
        title: String,
        layout: SceneLayout,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                SceneLayoutThumbnail(
                    sceneLayout: layout,
                    captureLayout: vm.settings.layout,
                    isSelected: isSelected
                )

                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(Color.white.opacity(isSelected ? 0.12 : 0.055), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isSelected ? Color(red: 0.09, green: 1.0, blue: 0.65).opacity(0.62) : Color.white.opacity(0.08),
                    lineWidth: 1
                )
        }
        .disabled(!vm.canEditScene)
        .opacity(vm.canEditScene || isSelected ? 1 : 0.45)
        .pointingHandCursor()
        .help(title)
    }
}

private struct SceneLayoutThumbnail: View {
    let sceneLayout: SceneLayout
    let captureLayout: CaptureLayout
    let isSelected: Bool

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = fittedCanvasSize(in: proxy.size)
            let x = (proxy.size.width - canvasSize.width) / 2
            let y = (proxy.size.height - canvasSize.height) / 2

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(canvasGradient)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(.white.opacity(isSelected ? 0.28 : 0.16), lineWidth: 1)
                    }

                ForEach(sceneLayout.layerOrder, id: \.self) { layer in
                    SceneLayoutThumbnailLayer(
                        kind: layer,
                        rect: thumbnailRect(for: layer, in: canvasSize),
                        isSelected: isSelected
                    )
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .offset(x: x, y: y)
        }
        .frame(width: 54, height: 44)
    }

    private var canvasGradient: LinearGradient {
        LinearGradient(
            colors: isSelected
                ? [
                    Color(red: 0.10, green: 0.12, blue: 0.15),
                    Color(red: 0.20, green: 0.23, blue: 0.29)
                ]
                : [
                    Color.white.opacity(0.12),
                    Color.white.opacity(0.045)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func fittedCanvasSize(in size: CGSize) -> CGSize {
        let aspectRatio = captureLayout.aspectRatio
        let availableRatio = size.width / max(size.height, 1)
        if availableRatio > aspectRatio {
            let height = size.height
            return CGSize(width: height * aspectRatio, height: height)
        }
        let width = size.width
        return CGSize(width: width, height: width / aspectRatio)
    }

    private func thumbnailRect(for layer: SceneLayerKind, in size: CGSize) -> CGRect {
        let frame = sceneLayout.frame(for: layer)
        return CGRect(
            x: frame.minX * size.width,
            y: (1 - frame.maxY) * size.height,
            width: frame.width * size.width,
            height: frame.height * size.height
        )
    }
}

private struct SceneLayoutThumbnailLayer: View {
    let kind: SceneLayerKind
    let rect: CGRect
    let isSelected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fill)
                .shadow(color: .black.opacity(kind == .camera ? 0.28 : 0.14), radius: 2, x: 0, y: 1)

            if kind == .screen {
                screenGlyph
            } else {
                cameraGlyph
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(kind == .camera ? 0.56 : 0.26), lineWidth: 0.7)
        }
        .frame(width: max(3, rect.width), height: max(3, rect.height))
        .offset(x: rect.minX, y: rect.minY)
    }

    private var cornerRadius: CGFloat {
        kind == .camera ? 4 : 3
    }

    private var fill: LinearGradient {
        switch kind {
        case .screen:
            return LinearGradient(
                colors: [
                    Color(red: 0.13, green: 0.48, blue: 0.96).opacity(isSelected ? 0.92 : 0.78),
                    Color(red: 0.08, green: 0.92, blue: 0.72).opacity(isSelected ? 0.72 : 0.58)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .camera:
            return LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.50, blue: 0.30).opacity(isSelected ? 0.96 : 0.82),
                    Color(red: 1.0, green: 0.18, blue: 0.44).opacity(isSelected ? 0.86 : 0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var screenGlyph: some View {
        VStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(.white.opacity(index == 0 ? 0.55 : 0.32))
                    .frame(width: lineWidth(for: index), height: 1.2)
            }
        }
        .opacity(rect.width > 14 && rect.height > 12 ? 1 : 0)
    }

    private var cameraGlyph: some View {
        VStack(spacing: 2) {
            Circle()
                .fill(.white.opacity(0.74))
                .frame(width: 5, height: 5)
            Capsule()
                .fill(.white.opacity(0.58))
                .frame(width: 12, height: 5)
        }
        .opacity(rect.width > 14 && rect.height > 12 ? 1 : 0)
    }

    private func lineWidth(for index: Int) -> CGFloat {
        switch index {
        case 0: return min(22, max(8, rect.width * 0.58))
        case 1: return min(18, max(7, rect.width * 0.46))
        default: return min(14, max(6, rect.width * 0.34))
        }
    }
}

private struct VideoSourceRow: View {
    let source: CaptureSource
    let title: String
    let symbol: String
    @Bindable var vm: RecorderViewModel

    @State private var isHovering = false

    private var enabled: Bool { vm.settings.enabledSources.contains(source) }

    var body: some View {
        VStack(alignment: .leading, spacing: showsSourceControls ? 10 : 0) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(enabled ? 0.7 : 0.4))
                    .frame(width: 18, height: 18)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(enabled ? 0.95 : 0.45))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                EyeToggle(enabled: enabled, title: title) {
                    vm.setSourceVisible(source, visible: !enabled)
                }
                .disabled(vm.state != .idle)

                RowOverflowMenu(
                    isVisible: isHovering,
                    disabled: vm.state != .idle,
                    removeTitle: "Remove \(title)"
                ) {
                    vm.removeSource(source)
                }
            }

            if source == .camera {
                WebcamSourceMenu(vm: vm, enabled: enabled)
                TransparentWebcamToggle(vm: vm, enabled: enabled)
            } else if source == .screen {
                ScreenSourcePickerRow(vm: vm, enabled: enabled)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, showsSourceControls ? 10 : 8)
        .opacity(enabled ? 1 : 0.62)
        .background(Color.white.opacity(0.055), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color(red: 0.09, green: 1.0, blue: 0.65).opacity(0.62) : Color.white.opacity(0.08), lineWidth: 1)
        }
        .contentShape(.rect(cornerRadius: 10))
        .onTapGesture {
            if let layer {
                vm.selectLayer(layer)
            }
        }
        .onHover { isHovering = $0 }
        .pointingHandCursor()
        .contextMenu {
            Button(enabled ? "Hide" : "Show") {
                vm.setSourceVisible(source, visible: !enabled)
            }
            .disabled(vm.state != .idle)
            if source == .screen {
                Button("Pick Screen...") {
                    vm.pickScreen()
                }
                .disabled(vm.state != .idle)
            }
            Divider()
            Button("Remove \(title)", role: .destructive) {
                vm.removeSource(source)
            }
            .disabled(vm.state != .idle)
        }
    }

    private var isSelected: Bool {
        layer == vm.selectedLayer && enabled
    }

    private var showsSourceControls: Bool {
        source == .screen || source == .camera
    }

    private var layer: SceneLayerKind? {
        switch source {
        case .screen:
            return .screen
        case .camera:
            return .camera
        case .microphone, .systemAudio:
            return nil
        }
    }
}

private struct ScreenSourcePickerRow: View {
    @Bindable var vm: RecorderViewModel
    let enabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            screenCaptureSource
            windowFitControls
        }
    }

    private var screenCaptureSource: some View {
        HStack(spacing: 8) {
            sourceIcon

            VStack(alignment: .leading, spacing: 1) {
                Text("Capture source")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(.white.opacity(enabled ? 0.38 : 0.24))
                Text(vm.screenCropLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(enabled ? 0.76 : 0.38))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)

            Button {
                vm.pickScreen()
            } label: {
                Label("Change source", systemImage: "rectangle.on.rectangle.angled")
                    .font(.system(size: 10, weight: .semibold))
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .disabled(vm.state != .idle)
            .pointingHandCursor()
            .help("Choose a display, app, or window for Screen")
        }
    }

    private var sourceIcon: some View {
        Image(systemName: vm.settings.usesPickedScreenContent ? "rectangle.dashed" : "display")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(enabled ? 0.5 : 0.28))
            .frame(width: 20, height: 20)
            .background(.white.opacity(enabled ? 0.07 : 0.035), in: .rect(cornerRadius: 6))
    }

    private var windowFitControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: vm.targetWindowInfo == nil ? "questionmark.app" : "app.window")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(enabled ? 0.5 : 0.28))
                    .frame(width: 20, height: 20)
                    .background(.white.opacity(enabled ? 0.07 : 0.035), in: .rect(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Window fit")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.5)
                        .foregroundStyle(.white.opacity(enabled ? 0.38 : 0.24))
                    Text(targetWindowLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(enabled ? 0.76 : 0.38))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)

                Button {
                    vm.refreshTargetWindow()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .pointingHandCursor()
                .help("Refresh active window")
            }

            HStack(spacing: 6) {
                fitScaleButton("75%", value: 0.75)
                fitScaleButton("100%", value: 1.0)
                fitScaleButton("125%", value: 1.25)
            }

            Slider(
                value: Binding(
                    get: { vm.targetWindowFitScale },
                    set: { value in
                        vm.fitFrontWindowForShorts(scale: CGFloat(value))
                    }
                ),
                in: 0.75...1.25,
                step: 0.05
            )
            .controlSize(.small)

            Button {
                vm.fitScreenItemToFrontWindow()
            } label: {
                Label("Capture active window only", systemImage: "rectangle.inset.filled")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .pointingHandCursor()
            .help("Show only the active app window inside the screen layer")
        }
        .disabled(!enabled)
    }

    private var targetWindowLabel: String {
        guard let target = vm.targetWindowInfo else {
            return vm.targetWindowStatus.isEmpty ? "No active window detected" : vm.targetWindowStatus
        }
        if target.detail.isEmpty {
            return target.title
        }
        return "\(target.title) · \(target.detail)"
    }

    private func fitScaleButton(_ title: String, value: Double) -> some View {
        let active = abs(vm.targetWindowFitScale - value) < 0.01
        return Button {
            vm.fitFrontWindowForShorts(scale: CGFloat(value))
        } label: {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 24)
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .tint(active ? Color(red: 0.09, green: 1.0, blue: 0.65).opacity(0.22) : .clear)
        .pointingHandCursor()
        .help("Fit the active window at \(title) of the scene screen slot")
    }
}

private struct AudioTrackRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let source: CaptureSource
    let levels: TrackLevels
    @Binding var gain: Double
    @Bindable var vm: RecorderViewModel

    @State private var isHovering = false

    private var enabled: Bool { vm.settings.enabledSources.contains(source) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(enabled ? 0.7 : 0.4))
                    .frame(width: 18, height: 18)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(enabled ? 0.95 : 0.45))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text("\(Int((gain * 100).rounded()))%")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .monospacedDigit()

                EyeToggle(enabled: enabled, title: title) {
                    vm.setSourceVisible(source, visible: !enabled)
                }
                .disabled(vm.state != .idle)

                RowOverflowMenu(
                    isVisible: isHovering,
                    disabled: vm.state != .idle,
                    removeTitle: "Remove \(title)"
                ) {
                    vm.removeSource(source)
                }
            }

            if source == .microphone {
                MicrophoneSourceMenu(vm: vm, enabled: enabled)
            } else if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(enabled ? 0.5 : 0.28))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(subtitle)
            }

            TrackLevelGraph(levels: levels, active: enabled)
                .frame(height: 22)
                .opacity(enabled ? 1 : 0.3)

            HStack(spacing: 6) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                Slider(value: $gain, in: 0...2)
                    .controlSize(.mini)
                    .disabled(vm.state != .idle || !enabled)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.055), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .contentShape(.rect(cornerRadius: 12))
        .onHover { isHovering = $0 }
        .pointingHandCursor()
        .contextMenu {
            Button(enabled ? "Mute" : "Unmute") {
                vm.setSourceVisible(source, visible: !enabled)
            }
            .disabled(vm.state != .idle)
            Button("Reset gain to 100%") {
                gain = 1.0
            }
            .disabled(vm.state != .idle || !enabled)
            Divider()
            Button("Remove \(title)", role: .destructive) {
                vm.removeSource(source)
            }
            .disabled(vm.state != .idle)
        }
    }
}

private struct MicrophoneSourceMenu: View {
    @Bindable var vm: RecorderViewModel
    let enabled: Bool

    var body: some View {
        Menu {
            Button {
                vm.setMicrophone(nil)
            } label: {
                Label("Default microphone", systemImage: vm.settings.selectedMicrophoneID == nil ? "checkmark" : "mic")
            }

            if !vm.availableMicrophones.isEmpty {
                Divider()
            }

            ForEach(vm.availableMicrophones, id: \.id) { option in
                Button {
                    vm.setMicrophone(option.id)
                } label: {
                    Label(option.name, systemImage: vm.settings.selectedMicrophoneID == option.id ? "checkmark" : "mic")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(vm.selectedMicrophoneDisplayName)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(enabled ? 0.42 : 0.24))
            }
            .foregroundStyle(.white.opacity(enabled ? 0.58 : 0.3))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect(cornerRadius: 7))
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .controlSize(.small)
        .disabled(vm.state != .idle)
        .pointingHandCursor()
        .help("Choose microphone source")
    }
}

private struct EyeToggle: View {
    let enabled: Bool
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: enabled ? "eye.fill" : "eye.slash.fill")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.glass)
        .foregroundStyle(.white.opacity(enabled ? 0.78 : 0.42))
        .pointingHandCursor()
        .help(enabled ? "Hide \(title)" : "Show \(title)")
    }
}

private struct RowOverflowMenu: View {
    let isVisible: Bool
    let disabled: Bool
    let removeTitle: String
    let onRemove: () -> Void

    var body: some View {
        Menu {
            Button(removeTitle, role: .destructive, action: onRemove)
                .disabled(disabled)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .bold))
                .frame(width: 22, height: 22)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .controlSize(.small)
        .foregroundStyle(.white.opacity(0.7))
        .opacity(isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.12), value: isVisible)
        .frame(width: 22, height: 22)
        .pointingHandCursor()
    }
}

private struct EmptySourceHint: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.38))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 10))
    }
}

private struct TrackLevelGraph: View {
    let levels: TrackLevels
    let active: Bool

    var body: some View {
        Canvas { context, size in
            let values = levels.levels
            guard !values.isEmpty else { return }

            let recentMax = max(0.08, (values.suffix(16).max() ?? 0) * 0.86)
            let barCount = values.count
            let spacing: CGFloat = 1
            let barWidth = max(1.5, (size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount))
            let centerY = size.height / 2
            let color = active
                ? Color(red: 0.09, green: 1.0, blue: 0.65)
                : Color.white.opacity(0.3)

            for (i, raw) in values.enumerated() {
                let normalized = raw > 0.003 ? max(0.04, min(1, raw / recentMax)) : 0.02
                let h = max(1.5, CGFloat(normalized) * size.height)
                let x = CGFloat(i) * (barWidth + spacing)
                let rect = CGRect(x: x, y: centerY - h / 2, width: barWidth, height: h)
                let alpha = 0.25 + 0.7 * CGFloat(normalized)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(color.opacity(alpha))
                )
            }
        }
    }
}

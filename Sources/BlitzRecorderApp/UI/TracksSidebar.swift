import SwiftUI

struct SourcesSidebar: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                sourcesSection

                if let selectedSource = vm.selectedSource?.source,
                   vm.isSourceConfigured(selectedSource) {
                    selectedSourceSection(selectedSource)
                }

                sidebarDivider

                sceneSection

                sidebarDivider

                canvasSection
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .frame(width: 340)
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
            RecordingOverlayControls(vm: vm)
                .disabled(vm.state != .idle)
                .opacity(vm.state == .idle ? 1 : 0.45)
        }
    }

    private var sidebarDivider: some View {
        Divider()
            .background(.white.opacity(0.08))
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            subHeader("Sources", icon: "rectangle.stack", addSources: inactiveSources)

            VStack(spacing: 6) {
                if shownSources.isEmpty {
                    EmptySourceHint(title: "No sources")
                }
                ForEach(shownVideoOrder, id: \.self) { kind in
                    sourceRow(for: captureSource(for: kind))
                        .draggable(kind.rawValue) {
                            sourceRow(for: captureSource(for: kind)).opacity(0.85)
                        }
                        .dropDestination(for: String.self) { items, _ in
                            return handleDrop(items, onto: kind)
                        }
                }
                ForEach(shownAudioSources, id: \.self) { source in
                    sourceRow(for: source)
                }
            }
        }
    }

    private var shownSources: [CaptureSource] {
        shownVideoOrder.map(captureSource(for:)) + shownAudioSources
    }

    private var shownVideoOrder: [SceneLayerKind] {
        SceneLayoutProjection.frontToBackOrder(for: vm.settings.sceneLayout)
            .filter { vm.isSourceConfigured(captureSource(for: $0)) }
    }

    private var shownAudioSources: [CaptureSource] {
        [.microphone, .systemAudio].filter { vm.isSourceConfigured($0) }
    }

    private var inactiveSources: [CaptureSource] {
        [
            CaptureSource.screen,
            .camera,
            .microphone,
            .systemAudio
        ].filter { !vm.isSourceConfigured($0) }
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

    @ViewBuilder
    private func sourceRow(for source: CaptureSource) -> some View {
        switch source {
        case .screen:
            SourceListRow(
                source: .screen,
                title: "Screen",
                subtitle: vm.screenCropLabel,
                status: sourceStatus(for: .screen),
                symbol: source.symbolName,
                vm: vm
            )
        case .camera:
            SourceListRow(
                source: .camera,
                title: "Camera",
                subtitle: vm.selectedCameraDisplayName,
                status: sourceStatus(for: .camera),
                symbol: source.symbolName,
                vm: vm
            )
        case .microphone:
            SourceListRow(
                source: .microphone,
                title: "Mic",
                subtitle: vm.selectedMicrophoneDisplayName,
                status: sourceStatus(for: .microphone),
                symbol: source.symbolName,
                levels: vm.micLevels,
                vm: vm
            )
        case .systemAudio:
            SourceListRow(
                source: .systemAudio,
                title: "System",
                subtitle: "Mac audio",
                status: sourceStatus(for: .systemAudio),
                symbol: source.symbolName,
                levels: vm.sysLevels,
                vm: vm
            )
        }
    }

    private func sourceStatus(for source: CaptureSource) -> SourceRowStatus {
        guard vm.isSourceVisible(source) else {
            return SourceRowStatus(label: source.isAudioSource ? "Muted" : "Hidden", tone: .muted)
        }

        if let recordingStatus = recordingStateStatus {
            return recordingStatus
        }

        if vm.recordingReadiness.blockers.contains(where: { $0.source == source }) {
            return SourceRowStatus(label: "No access", tone: .warning)
        }

        switch source {
        case .screen:
            if vm.settings.usesPickedScreenContent {
                return SourceRowStatus(label: "Picked", tone: .active)
            }
            return SourceRowStatus(label: "Display", tone: .active)
        case .camera:
            if vm.isRemoteCameraSelected {
                return remoteCameraStatus
            }
            return SourceRowStatus(label: "Local", tone: .active)
        case .microphone:
            return SourceRowStatus(label: "Input", tone: .active)
        case .systemAudio:
            return SourceRowStatus(label: "System", tone: .active)
        }
    }

    private var recordingStateStatus: SourceRowStatus? {
        switch vm.state {
        case .idle:
            return nil
        case .recording:
            return SourceRowStatus(label: "Live", tone: .active)
        case .paused:
            return SourceRowStatus(label: "Paused", tone: .muted)
        case .starting, .finishing:
            return SourceRowStatus(label: "Locked", tone: .muted)
        }
    }

    private var remoteCameraStatus: SourceRowStatus {
        let status = (vm.selectedRemoteCameraStatus ?? vm.selectedRemoteCameraReviewStatus).lowercased()
        if status.contains("waiting") || status.contains("disconnect") || status.contains("unavailable") {
            return SourceRowStatus(label: "Waiting", tone: .warning)
        }
        return SourceRowStatus(label: "iPhone", tone: .active)
    }

    @ViewBuilder
    private func selectedSourceSection(_ source: CaptureSource) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            subHeader("\(source.shortLabel) Inspector", icon: source.symbolName)

            switch source {
            case .screen:
                ScreenSourceInspector(vm: vm, enabled: vm.isSourceConfigured(.screen))
            case .camera:
                CameraSourceInspector(vm: vm, enabled: vm.isSourceConfigured(.camera))
            case .microphone:
                AudioSourceInspector(
                    title: "Mic gain",
                    source: .microphone,
                    levels: vm.micLevels,
                    gain: Binding(get: { vm.settings.microphoneGain }, set: { vm.setMicrophoneGain($0) }),
                    vm: vm
                )
            case .systemAudio:
                AudioSourceInspector(
                    title: "System gain",
                    source: .systemAudio,
                    levels: vm.sysLevels,
                    gain: Binding(get: { vm.settings.systemAudioGain }, set: { vm.setSystemAudioGain($0) }),
                    vm: vm
                )
            }
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
                            colors: style.appearance.swatchColors,
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

            if !vm.remoteCameraOptions.isEmpty {
                Divider()

                ForEach(vm.remoteCameraOptions, id: \.id) { option in
                    Button {
                        vm.setCamera(option.id)
                    } label: {
                        Label(option.name, systemImage: vm.settings.selectedCameraID == option.id ? "checkmark" : "iphone.gen3")
                    }
                }
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
        .help("Choose camera source")
    }
}

private struct SceneLayoutControls: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                ForEach(supportedPresets, id: \.self) { preset in
                    sceneCell(
                        title: preset.rawValue,
                        layout: SceneLayout.presetLayout(
                            preset,
                            for: vm.settings.layout
                        ),
                        isSelected: vm.settings.selectedScenePreset == preset
                    ) {
                        vm.setScenePreset(preset)
                    }
                }
                if vm.settings.selectedScenePreset == nil {
                    sceneCell(
                        title: "Custom",
                        layout: vm.settings.sceneLayout,
                        isSelected: true
                    ) {}
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
            VStack(spacing: 8) {
                SceneLayoutThumbnail(
                    sceneLayout: layout,
                    captureLayout: vm.settings.layout
                )

                HStack(spacing: 4) {
                    Text(shortSceneTitle(title))
                        .lineLimit(1)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color(red: 0.09, green: 1.0, blue: 0.65))
                    }
                }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.62))
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 74)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(Color.white.opacity(isSelected ? 0.10 : 0.045), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isSelected ? Color(red: 0.09, green: 1.0, blue: 0.65).opacity(0.58) : Color.white.opacity(0.08),
                    lineWidth: 1
                )
        }
        .disabled(!vm.canEditScene)
        .opacity(vm.canEditScene || isSelected ? 1 : 0.45)
        .pointingHandCursor()
        .help(title)
    }

    private func shortSceneTitle(_ title: String) -> String {
        switch title {
        case ScenePreset.screenTop50.rawValue:
            return "Split"
        case ScenePreset.screenFullscreen.rawValue:
            return "Screen"
        case ScenePreset.webcamFullscreen.rawValue:
            return "Webcam"
        default:
            return title.replacingOccurrences(of: " Fullscreen", with: "")
        }
    }
}

private struct ScreenSplitHeightControl: View {
    @Bindable var vm: RecorderViewModel

    private var screenPercent: Int {
        Int((vm.screenSplitHeight * 100).rounded())
    }

    private var cameraPercent: Int {
        100 - screenPercent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.and.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 18, height: 18)
                Text("Split height")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer(minLength: 0)
                Text("Screen \(screenPercent)%")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.68))
            }

            Slider(
                value: Binding(
                    get: { vm.screenSplitHeight },
                    set: { vm.setScreenSplitHeight($0) }
                ),
                in: Double(SceneLayout.minimumScreenSplitHeight)...Double(SceneLayout.maximumScreenSplitHeight),
                step: 0.01
            )
            .controlSize(.mini)
            .disabled(!vm.canEditScene)

            HStack {
                Text("Webcam \(cameraPercent)%")
                Spacer(minLength: 0)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.5))
        }
        .opacity(vm.canEditScene ? 1 : 0.45)
    }
}

private struct SceneLayoutThumbnail: View {
    let sceneLayout: SceneLayout
    let captureLayout: CaptureLayout

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
                            .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                    }

                ForEach(sceneLayout.layerOrder, id: \.self) { layer in
                    SceneLayoutThumbnailLayer(
                        kind: layer,
                        rect: thumbnailRect(for: layer, in: canvasSize)
                    )
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .offset(x: x, y: y)
        }
        .frame(width: 66, height: 48)
    }

    private var canvasGradient: LinearGradient {
        LinearGradient(
            colors: [
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
                    Color(red: 0.13, green: 0.48, blue: 0.96).opacity(0.78),
                    Color(red: 0.08, green: 0.92, blue: 0.72).opacity(0.58)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .camera:
            return LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.50, blue: 0.30).opacity(0.82),
                    Color(red: 1.0, green: 0.18, blue: 0.44).opacity(0.72)
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

private struct SourceListRow: View {
    let source: CaptureSource
    let title: String
    let subtitle: String
    let status: SourceRowStatus
    let symbol: String
    var levels: TrackLevels?
    @Bindable var vm: RecorderViewModel

    private var enabled: Bool { vm.settings.enabledSources.contains(source) }
    private var visible: Bool { vm.isSourceVisible(source) }
    private var isSelected: Bool { vm.selectedSource?.source == source }

    var body: some View {
        Button {
            vm.selectSource(source)
        } label: {
            HStack(spacing: 12) {
                sourceIcon

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(visible ? 0.95 : 0.45))
                            .lineLimit(1)

                        if status.tone == .warning {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.22).opacity(0.9))
                                .help(status.label)
                        }
                    }

                    Text(rowSubtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(visible ? 0.52 : 0.28))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)

                if let levels {
                    TrackLevelGraph(levels: levels, active: visible)
                        .frame(width: 34, height: 16)
                        .opacity(visible ? 1 : 0.3)
                }

                Toggle("", isOn: Binding(
                    get: { visible },
                    set: { vm.setSourceVisible(source, visible: $0) }
                ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .disabled(vm.state != .idle)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .opacity(visible ? 1 : 0.62)
        .background(Color.white.opacity(isSelected ? 0.11 : 0.055), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isSelected ? Color(red: 0.09, green: 1.0, blue: 0.65).opacity(0.62) : Color.white.opacity(0.08),
                    lineWidth: 1
                )
        }
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule()
                    .fill(Color(red: 0.09, green: 1.0, blue: 0.65).opacity(0.82))
                    .frame(width: 3, height: 28)
                    .padding(.leading, 1)
            }
        }
        .pointingHandCursor()
        .contextMenu {
            Button(visible ? "Hide" : "Show") {
                vm.setSourceVisible(source, visible: !visible)
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

    private var sourceIcon: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(iconColor.opacity(visible ? 0.82 : 0.34))
            .frame(width: 24, height: 24)
            .background(.white.opacity(visible ? 0.07 : 0.035), in: .rect(cornerRadius: 7))
    }

    private var iconColor: Color {
        if status.tone == .warning {
            return Color(red: 1.0, green: 0.72, blue: 0.22)
        }
        return Color.white
    }

    private var rowSubtitle: String {
        guard visible else { return source.isAudioSource ? "Muted" : "Hidden" }
        switch source {
        case .screen:
            if subtitle == "Full display" {
                return vm.settings.usesPickedScreenContent ? "Picked content" : "Full display"
            }
            return subtitle
        case .camera, .microphone, .systemAudio:
            return subtitle
        }
    }
}

private struct SourceRowStatus: Equatable {
    let label: String
    let tone: SourceRowStatusTone
}

private enum SourceRowStatusTone: Equatable {
    case active
    case muted
    case warning
}

private struct ScreenSourceInspector: View {
    @Bindable var vm: RecorderViewModel
    let enabled: Bool
    private let accent = Color(red: 0.09, green: 1.0, blue: 0.65)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            captureSourceRow
            screenSettingsDivider
            captureAreaControl
            if showsSplitHeightControls {
                screenSettingsDivider
                ScreenSplitHeightControl(vm: vm)
            }
        }
        .settingsPanelStyle()
    }

    private var captureSourceRow: some View {
        HStack(spacing: 10) {
            inspectorIcon(vm.settings.usesPickedScreenContent ? "rectangle.dashed" : "display", enabled: enabled)

            VStack(alignment: .leading, spacing: 2) {
                inspectorLabel("Source", enabled: enabled)
                Text(captureSourceLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(enabled ? 0.82 : 0.38))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)

            screenSettingIconButton(
                "rectangle.on.rectangle",
                help: "Choose a display, app, or window",
                disabled: vm.state != .idle
            ) {
                vm.pickScreen()
            }
        }
    }

    private var captureAreaControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                inspectorIcon("crop", enabled: enabled)

                inspectorLabel("Capture area", enabled: enabled)

                Spacer(minLength: 0)
            }

            HStack(spacing: 4) {
                captureAreaButton(
                    "Full",
                    icon: "display",
                    isSelected: vm.screenCaptureAreaSelection == .fullDisplay,
                    help: "Capture the full selected display or picked content"
                ) {
                    vm.clearScreenCrop()
                }

                captureAreaButton(
                    "Window",
                    icon: "app.window",
                    isSelected: vm.screenCaptureAreaSelection == .activeWindow,
                    help: "Fit capture to the active window"
                ) {
                    vm.fitScreenItemToFrontWindow()
                }

                captureAreaButton(
                    "Crop",
                    icon: "crop",
                    isSelected: vm.screenCaptureAreaSelection == .manualCrop,
                    help: "Pick a manual screen crop"
                ) {
                    vm.selectScreenCrop()
                }
            }
            .disabled(!enabled || vm.state != .idle)

            cropStatusRow

            if vm.screenCaptureAreaSelection == .activeWindow {
                windowScaleControl
            }
            if vm.isScreenCropModeEnabled {
                cropModeStatus
            }
        }
    }

    private var cropStatusRow: some View {
        HStack(spacing: 8) {
            Image(systemName: captureAreaStatusIcon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(enabled ? 0.45 : 0.24))
                .frame(width: 16, height: 16)

            Text(captureAreaLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(enabled ? 0.58 : 0.3))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            if vm.settings.screenCrop != nil || vm.isScreenCropModeEnabled {
                Button {
                    vm.clearScreenCrop()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .disabled(!enabled || vm.state != .idle)
                .pointingHandCursor()
                .help("Reset crop")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.white.opacity(0.04), in: .rect(cornerRadius: 8))
    }

    private var cropModeStatus: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock")
                .font(.system(size: 10, weight: .semibold))
            Text("Scene locked while cropping")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(accent.opacity(enabled ? 0.86 : 0.38))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(accent.opacity(0.10), in: .rect(cornerRadius: 8))
    }

    private var windowScaleControl: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                inspectorIcon("app.window", enabled: enabled)

                VStack(alignment: .leading, spacing: 1) {
                    inspectorLabel("Active window", enabled: enabled)
                    Text(targetWindowLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(enabled ? 0.76 : 0.38))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)

                screenSettingIconButton(
                    "arrow.clockwise",
                    help: "Refresh active window",
                    disabled: false
                ) {
                    vm.refreshTargetWindow()
                }
            }

            Divider()
                .background(.white.opacity(0.07))

            HStack(spacing: 8) {
                Text("Fit scale")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(enabled ? 0.56 : 0.3))
                Spacer(minLength: 0)
                Text(windowScaleLabel)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(enabled ? 0.78 : 0.38))
                    .monospacedDigit()

                screenSettingIconButton(
                    "arrow.counterclockwise",
                    help: "Reset window scale to 100%",
                    disabled: false
                ) {
                    vm.fitFrontWindowForShorts(scale: 1.0)
                }
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
            .disabled(!enabled)

            HStack {
                Text("75%")
                Spacer(minLength: 0)
                Text("100%")
                Spacer(minLength: 0)
                Text("125%")
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(enabled ? 0.34 : 0.2))
            .monospacedDigit()
        }
        .padding(8)
        .background(.white.opacity(0.035), in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.07), lineWidth: 1)
        }
    }

    private var showsSplitHeightControls: Bool {
        vm.settings.layout == .vertical
            && vm.isSourceConfigured(.screen)
            && vm.isSourceConfigured(.camera)
            && (vm.settings.selectedScenePreset == .screenTop50
                || vm.settings.sceneLayout.screenSplitHeight != nil)
    }

    private var screenSettingsDivider: some View {
        Divider()
            .background(.white.opacity(0.08))
    }

    private var captureSourceLabel: String {
        vm.settings.usesPickedScreenContent ? "Picked screen content" : "Display capture"
    }

    private var captureAreaLabel: String {
        if vm.isScreenCropModeEnabled {
            return "Editing capture crop"
        }
        guard vm.settings.screenCrop != nil else {
            return vm.settings.usesPickedScreenContent ? "Picked content" : "Full display"
        }
        return vm.screenCropLabel
    }

    private var captureAreaStatusIcon: String {
        switch vm.screenCaptureAreaSelection {
        case .fullDisplay:
            return vm.settings.usesPickedScreenContent ? "rectangle.dashed" : "display"
        case .activeWindow:
            return "app.window"
        case .manualCrop:
            return "crop"
        }
    }

    private var windowScaleLabel: String {
        "\(Int((vm.targetWindowFitScale * 100).rounded()))%"
    }

    private func captureAreaButton(
        _ title: String,
        icon: String,
        isSelected: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white.opacity(isSelected ? 0.95 : 0.62))
            .frame(maxWidth: .infinity, minHeight: 44)
            .multilineTextAlignment(.center)
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .background(.white.opacity(isSelected ? 0.12 : 0.045), in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? accent.opacity(0.58) : .white.opacity(0.08), lineWidth: 1)
        }
        .pointingHandCursor()
        .help(help)
    }

    private func screenSettingIconButton(
        _ icon: String,
        help: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .disabled(!enabled || disabled)
        .pointingHandCursor()
        .help(help)
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

}

private struct CameraSourceInspector: View {
    @Bindable var vm: RecorderViewModel
    let enabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                InspectorMetricRow(
                    icon: vm.isRemoteCameraSelected ? "iphone.gen3" : "video",
                    title: "Selected",
                    value: vm.selectedCameraDisplayName,
                    enabled: enabled
                )
                WebcamSourceMenu(vm: vm, enabled: enabled)
                TransparentWebcamToggle(vm: vm, enabled: enabled)
            }
            .settingsPanelStyle()

            CameraCropControls(vm: vm)
        }
    }
}

private struct RecordingOverlayControls: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        VStack(spacing: 0) {
            OverlayToggleRow(
                symbol: "cursorarrow",
                title: "Show cursor",
                isOn: Binding(
                    get: { vm.settings.includeCursor },
                    set: { vm.setCursorIncluded($0) }
                )
            )
            Divider().background(.white.opacity(0.08)).padding(.horizontal, 12)
            OverlayToggleRow(
                symbol: "grid",
                title: "Rule of thirds",
                isOn: Binding(
                    get: { vm.settings.showsRuleOfThirdsOverlay },
                    set: { vm.setRuleOfThirds($0) }
                )
            )
            Divider().background(.white.opacity(0.08)).padding(.horizontal, 12)
            SafeZonePickerRow(
                selected: Binding(
                    get: { vm.settings.socialSafeZoneOverlay },
                    set: { vm.setSocialSafeZoneOverlay($0) }
                ),
                disabled: vm.settings.layout != .vertical
            )
        }
        .background(Color.white.opacity(0.055), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct AudioSourceInspector: View {
    let title: String
    let source: CaptureSource
    let levels: TrackLevels
    @Binding var gain: Double
    @Bindable var vm: RecorderViewModel

    private var enabled: Bool { vm.settings.enabledSources.contains(source) }
    private var gainLabel: String { "\(Int((gain * 100).rounded()))%" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(enabled ? 0.82 : 0.38))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(gainLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .monospacedDigit()
            }

            if source == .microphone {
                InspectorMetricRow(
                    icon: "mic",
                    title: "Selected",
                    value: vm.selectedMicrophoneDisplayName,
                    enabled: enabled
                )
                MicrophoneSourceMenu(vm: vm, enabled: enabled)
            } else {
                InspectorMetricRow(
                    icon: "speaker.wave.2",
                    title: "Selected",
                    value: "Mac audio",
                    enabled: enabled
                )
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
        .settingsPanelStyle()
    }
}

private struct InspectorMetricRow: View {
    let icon: String
    let title: String
    let value: String
    let enabled: Bool

    var body: some View {
        HStack(spacing: 8) {
            inspectorIcon(icon, enabled: enabled)

            VStack(alignment: .leading, spacing: 1) {
                inspectorLabel(title, enabled: enabled)
                Text(value)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(enabled ? 0.76 : 0.38))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct InspectorActionRow: View {
    let icon: String
    let title: String
    let value: String
    let enabled: Bool
    let actionIcon: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            inspectorIcon(icon, enabled: enabled)

            VStack(alignment: .leading, spacing: 1) {
                inspectorLabel(title, enabled: enabled)
                Text(value)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(enabled ? 0.76 : 0.38))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)

            Button(action: action) {
                Image(systemName: actionIcon)
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .pointingHandCursor()
        }
    }
}

private func inspectorIcon(_ icon: String, enabled: Bool) -> some View {
    Image(systemName: icon)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.white.opacity(enabled ? 0.5 : 0.28))
        .frame(width: 20, height: 20)
        .background(.white.opacity(enabled ? 0.07 : 0.035), in: .rect(cornerRadius: 6))
}

private func inspectorLabel(_ title: String, enabled: Bool) -> some View {
    Text(title.uppercased())
        .font(.system(size: 9, weight: .heavy))
        .tracking(0.5)
        .foregroundStyle(.white.opacity(enabled ? 0.38 : 0.24))
}

private func inspectorText(title: String, value: String, enabled: Bool) -> some View {
    VStack(alignment: .leading, spacing: 1) {
        inspectorLabel(title, enabled: enabled)
        Text(value)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(enabled ? 0.76 : 0.38))
            .lineLimit(1)
            .truncationMode(.tail)
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

private extension View {
    func settingsPanelStyle() -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.055), in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }
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

#if DEBUG
#Preview("Sources - Screen") {
    SourcesSidebar(vm: SourcesSidebarPreviewFactory.screenSelected())
        .frame(height: 780)
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
}

#Preview("Sources - Camera") {
    SourcesSidebar(vm: SourcesSidebarPreviewFactory.cameraSelected())
        .frame(height: 780)
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
}

#Preview("Sources - Mic") {
    SourcesSidebar(vm: SourcesSidebarPreviewFactory.micSelected())
        .frame(height: 780)
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
}

@MainActor
private enum SourcesSidebarPreviewFactory {
    static func screenSelected() -> RecorderViewModel {
        var settings = previewSettings
        settings.usesPickedScreenContent = true
        settings.selectedScenePreset = .screenTop50
        let vm = makeViewModel(settings: settings)
        vm.selectedSource = .screen
        vm.selectedLayer = .screen
        return vm
    }

    static func cameraSelected() -> RecorderViewModel {
        var settings = previewSettings
        settings.selectedScenePreset = .cameraInset
        settings.selectedCameraID = "preview-camera"
        let vm = makeViewModel(settings: settings)
        vm.selectedSource = .camera
        vm.selectedLayer = .camera
        return vm
    }

    static func micSelected() -> RecorderViewModel {
        var settings = previewSettings
        settings.enabledSources = [.screen, .camera, .microphone]
        settings.hiddenSources = [.camera]
        settings.selectedMicrophoneID = "preview-mic"
        let vm = makeViewModel(settings: settings)
        vm.selectedSource = .microphone
        return vm
    }

    private static var previewSettings: RecordingSettings {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen, .camera, .microphone, .systemAudio]
        settings.hiddenSources = []
        settings.sceneLayout = SceneLayout.screenSplitLayout(
            screenHeight: SceneLayout.defaultScreenSplitHeight
        )
        settings.canvasBackgroundStyle = .graphite
        return settings
    }

    private static func makeViewModel(settings: RecordingSettings) -> RecorderViewModel {
        let suiteName = "BlitzRecorder.SourcesSidebarPreview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        RecordingSettingsStore.save(settings, defaults: defaults)

        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults),
            defaults: defaults
        )
        let vm = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        vm.settings = settings
        vm.availableDisplays = [
            SourceOption(id: "display-1", name: "Studio Display")
        ]
        vm.availableCameras = [
            SourceOption(id: "preview-camera", name: "FaceTime HD Camera")
        ]
        vm.availableMicrophones = [
            SourceOption(id: "preview-mic", name: "Studio Mic")
        ]
        vm.targetWindowInfo = TargetWindowInfo(
            appName: "Safari",
            windowTitle: "Landing Page",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )
        vm.targetWindowStatus = "Safari - Landing Page"
        previewLevels.forEach { vm.micLevels.append($0) }
        previewLevels.reversed().forEach { vm.sysLevels.append($0) }
        return vm
    }

    private static var previewLevels: [Float] {
        [0.12, 0.28, 0.42, 0.22, 0.68, 0.38, 0.52, 0.31, 0.74, 0.49, 0.26, 0.58]
    }
}
#endif

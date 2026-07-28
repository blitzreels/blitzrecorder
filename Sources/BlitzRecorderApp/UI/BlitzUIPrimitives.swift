import AppKit
import SwiftUI

enum BlitzUI {
    static let mint = Color(red: 0.09, green: 1.0, blue: 0.65)
    static let orange = Color(red: 1.0, green: 0.66, blue: 0.16)
    static let recordRed = Color(red: 1.0, green: 0.27, blue: 0.27)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.22)
    static let panelStroke = Color.white.opacity(0.10)
    static let canvasBackground = Color(red: 0.035, green: 0.035, blue: 0.043)
    static let quietFill = Color.white.opacity(0.045)
    static let selectedFill = Color.white.opacity(0.16)
    static let controlFill = Color.white.opacity(0.055)
    static let cardFill = Color.white.opacity(0.055)
    static let separator = Color.white.opacity(0.08)

    static let trackScreen = Color.cyan
    static let trackCamera = Color.teal
    static let trackMicrophone = Color(red: 0.72, green: 0.54, blue: 1.0)
    static let trackSystemAudio = Color(red: 0.36, green: 0.56, blue: 1.0)

    static func levelColor(active: Bool) -> Color {
        active ? mint : Color.white.opacity(0.3)
    }

    static func sectionLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.62))
                .frame(width: 16, height: 16)

            Text(title.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(1)
        }
    }
}

struct BlitzIconTile: View {
    let symbolName: String
    let isSelected: Bool
    var icon: NSImage? = nil
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? BlitzUI.mint.opacity(0.16) : BlitzUI.controlFill)
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.68, height: size * 0.68)
                    .clipShape(.rect(cornerRadius: 4))
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: max(10, size * 0.43), weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? BlitzUI.mint : .white.opacity(0.58))
            }
        }
        .frame(width: size, height: size)
    }
}

struct BlitzScenePresetCard: View {
    let preset: ScenePreset
    let layout: CaptureLayout
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                BlitzSceneLayoutThumbnail(
                    layout: layout,
                    sceneLayout: SceneLayout.presetLayout(preset, for: layout),
                    visibleSources: visibleSources
                )
                .frame(height: 46)

                Text(preset.compactTitle)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 82)
            .background(cardFill, in: .rect(cornerRadius: 13))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(cardStroke, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            .contentShape(.rect)
        }
        .buttonStyle(BlitzScenePresetButtonStyle())
        .contentShape(.rect)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .animation(.easeOut(duration: 0.18), value: isSelected)
        .disabled(!isEnabled)
        .opacity(isEnabled || isSelected ? 1 : 0.5)
        .pointingHandCursor()
        .help(preset.rawValue)
    }

    private var visibleSources: Set<CaptureSource> {
        switch preset {
        case .screenFullscreen:
            return [.screen]
        case .webcamFullscreen:
            return [.camera]
        default:
            return [.screen, .camera]
        }
    }

    private var cardFill: Color {
        if isSelected {
            return .white.opacity(0.1)
        }
        return isHovering ? .white.opacity(0.075) : .white.opacity(0.045)
    }

    private var cardStroke: Color {
        if isSelected {
            return .white.opacity(0.26)
        }
        return .white.opacity(isHovering ? 0.13 : 0.06)
    }

    private var titleColor: Color {
        if isSelected {
            return .white.opacity(0.96)
        }
        return .white.opacity(isHovering ? 0.8 : 0.62)
    }
}

struct BlitzScenePresetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.11), value: configuration.isPressed)
    }
}

struct BlitzSceneLayoutThumbnail: View {
    let layout: CaptureLayout
    let sceneLayout: SceneLayout
    let visibleSources: Set<CaptureSource>

    var body: some View {
        GeometryReader { proxy in
            let canvas = fittedCanvas(in: proxy.size)
            let items = sceneLayout.resolvedItems(
                enabledSources: visibleSources,
                fillsCanvasWhenOnlyVideoSource: true
            )

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.black.opacity(0.16))
                    .frame(width: canvas.width, height: canvas.height)

                ForEach(items, id: \.kind) { item in
                    let frame = item.normalizedFrame.standardized
                    BlitzSceneThumbnailLayer(kind: item.kind)
                        .frame(
                            width: max(4, frame.width * canvas.width),
                            height: max(4, frame.height * canvas.height)
                        )
                        .offset(
                            x: frame.minX * canvas.width,
                            y: (1 - frame.maxY) * canvas.height
                        )
                }
            }
            .frame(width: canvas.width, height: canvas.height)
            .clipShape(.rect(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
            }
            .offset(x: canvas.minX, y: canvas.minY)
        }
        .accessibilityHidden(true)
    }

    private func fittedCanvas(in slot: CGSize) -> CGRect {
        guard slot.width > 0, slot.height > 0 else { return .zero }
        let aspect = layout.aspectRatio
        var width = slot.width
        var height = width / aspect
        if height > slot.height {
            height = slot.height
            width = height * aspect
        }
        return CGRect(
            x: (slot.width - width) / 2,
            y: (slot.height - height) / 2,
            width: width,
            height: height
        )
    }
}

private struct BlitzSceneThumbnailLayer: View {
    let kind: SceneLayerKind

    var body: some View {
        GeometryReader { proxy in
            if kind == .screen {
                screenLayer(size: proxy.size)
            } else {
                cameraLayer(size: proxy.size)
            }
        }
    }

    private func screenLayer(size: CGSize) -> some View {
        let radius = min(5, max(2, min(size.width, size.height) * 0.12))
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(.white.opacity(0.18))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(.white.opacity(0.46), lineWidth: 1)
        }
    }

    private func cameraLayer(size: CGSize) -> some View {
        let radius = min(6, max(2, min(size.width, size.height) * 0.16))
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(BlitzUI.mint.opacity(0.9))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(.white.opacity(0.24), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
    }
}

extension ScenePreset {
    var compactTitle: String {
        switch self {
        case .screenTop50:
            return "Split"
        case .cameraInset:
            return "Inset"
        case .webcamLeft:
            return "Left Cam"
        case .screenFullscreen:
            return "Screen"
        case .webcamFullscreen:
            return "Camera"
        default:
            return detail
        }
    }
}

enum BlitzStatusTone: Equatable {
    case live
    case ready
    case warning
    case muted

    var color: Color {
        switch self {
        case .live, .ready: return BlitzUI.mint
        case .warning: return BlitzUI.warning
        case .muted: return Color.white.opacity(0.3)
        }
    }
}

struct BlitzStatusDot: View {
    var tone: BlitzStatusTone
    var diameter: CGFloat = 7

    var body: some View {
        Circle()
            .fill(tone.color)
            .frame(width: diameter, height: diameter)
            .overlay {
                if tone == .live {
                    Circle()
                        .stroke(tone.color.opacity(0.35), lineWidth: diameter * 0.6)
                        .blur(radius: 1.2)
                }
            }
    }
}

struct BlitzLevelMeter: View {
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
            let color = BlitzUI.levelColor(active: active)

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

struct BlitzSelectedSurface: ViewModifier {
    let isSelected: Bool
    var cornerRadius: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .background(isSelected ? BlitzUI.selectedFill : BlitzUI.quietFill, in: .rect(cornerRadius: cornerRadius))
    }
}

extension View {
    func blitzSelectedSurface(isSelected: Bool, cornerRadius: CGFloat = 10) -> some View {
        modifier(BlitzSelectedSurface(isSelected: isSelected, cornerRadius: cornerRadius))
    }
}


struct BlitzMenuItem {
    var title: String
    var subtitle: String?
    var systemImage: String
    var icon: NSImage?
    var isSelected: Bool
    var isDestructive: Bool
    var action: () -> Void

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        icon: NSImage? = nil,
        isSelected: Bool = false,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.icon = icon
        self.isSelected = isSelected
        self.isDestructive = isDestructive
        self.action = action
    }
}

enum BlitzMenuEntry {
    case item(BlitzMenuItem)
    case divider
    case section(String)
}

struct BlitzGlassMenu<Label: View>: View {
    let entries: [BlitzMenuEntry]
    var menuWidth: CGFloat = 240
    @ViewBuilder var label: () -> Label

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            BlitzGlassMenuList(entries: entries, width: menuWidth, maxHeight: adaptivePopoverMaxHeight) {
                isPresented = false
            }
            .preferredColorScheme(.dark)
        }
    }

    private var adaptivePopoverMaxHeight: CGFloat {
        let visibleHeight = NSScreen.main?.visibleFrame.height ?? 720
        return min(520, max(260, visibleHeight - 120))
    }
}

struct BlitzSourcePickerItem {
    let title: String
    let subtitle: String?
    let systemImage: String
    let icon: NSImage?
    let thumbnail: NSImage?
    let isSelected: Bool
    let action: () -> Void
}

struct BlitzSourcePickerSection {
    let title: String
    let items: [BlitzSourcePickerItem]
}

struct BlitzSourcePickerModel {
    enum Layout {
        case list
        case thumbnails
    }

    let title: String
    let subtitle: String
    let systemImage: String
    let icon: NSImage?
    let sections: [BlitzSourcePickerSection]
    let actions: [BlitzSourcePickerItem]
    let layout: Layout
    let enabled: Bool
    var hiddenSections: [BlitzSourcePickerSection] = []
}

struct BlitzSourcePicker: View {
    let model: BlitzSourcePickerModel

    @State private var isPresented = false
    @State private var isHovering = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 10) {
                sourceIcon

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(model.enabled ? 0.94 : 0.38))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(model.subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(model.enabled ? 0.5 : 0.28))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 4)

                Text("Change")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(model.enabled ? 0.68 : 0.28))

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(model.enabled ? 0.42 : 0.2))
            }
            .padding(.horizontal, 10)
            .frame(height: 54)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.white.opacity(isHovering ? 0.085 : 0.05),
                in: .rect(cornerRadius: 9)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(.white.opacity(isHovering ? 0.16 : 0.1), lineWidth: 1)
            }
            .contentShape(.rect(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .disabled(!model.enabled)
        .onHover { isHovering = $0 }
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            BlitzSourcePickerPopover(model: model) {
                isPresented = false
            }
            .preferredColorScheme(.dark)
        }
        .pointingHandCursor()
    }

    @ViewBuilder
    private var sourceIcon: some View {
        if let icon = model.icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .padding(5)
                .background(BlitzUI.mint.opacity(0.12), in: .rect(cornerRadius: 8))
                .clipShape(.rect(cornerRadius: 8))
        } else {
            Image(systemName: model.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(model.enabled ? BlitzUI.mint : .white.opacity(0.28))
                .frame(width: 34, height: 34)
                .background(BlitzUI.mint.opacity(model.enabled ? 0.12 : 0.04), in: .rect(cornerRadius: 8))
        }
    }
}

private struct BlitzSourcePickerPopover: View {
    let model: BlitzSourcePickerModel
    let dismiss: () -> Void

    @State private var showsHiddenSections = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Choose source")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.94))
                Text("Choose exactly what this device records.")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
            }
            .padding(.horizontal, 14)
            .padding(.top, 13)
            .padding(.bottom, 10)

            Divider()
                .overlay(BlitzUI.separator)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(visibleSections.enumerated()), id: \.offset) { _, section in
                        if !section.items.isEmpty {
                            sourceSection(section)
                        }
                    }

                    if !model.hiddenSections.isEmpty {
                        hiddenSectionsButton
                    }
                }
                .padding(10)
            }
            .scrollIndicators(.visible)
            .frame(maxHeight: 420)

            if !model.actions.isEmpty {
                Divider()
                    .overlay(BlitzUI.separator)

                VStack(spacing: 4) {
                    ForEach(Array(model.actions.enumerated()), id: \.offset) { _, item in
                        BlitzSourcePickerActionRow(item: item, dismiss: dismiss)
                    }
                }
                .padding(8)
            }
        }
        .frame(width: model.layout == .thumbnails ? 520 : 330)
    }

    private var visibleSections: [BlitzSourcePickerSection] {
        model.sections + (showsHiddenSections ? model.hiddenSections : [])
    }

    private var hiddenSectionsButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                showsHiddenSections.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: showsHiddenSections ? "eye.slash" : "eye")
                Text(showsHiddenSections ? "Hide private apps" : "Show all apps")
                Spacer(minLength: 0)
                Image(systemName: showsHiddenSections ? "chevron.up" : "chevron.down")
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.62))
            .padding(.horizontal, 9)
            .frame(minHeight: 36)
            .background(Color.white.opacity(0.035), in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private func sourceSection(_ section: BlitzSourcePickerSection) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(section.title.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.7)
                .foregroundStyle(.white.opacity(0.4))
                .padding(.horizontal, 4)

            if model.layout == .thumbnails {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                        BlitzSourcePickerThumbnailCard(item: item, dismiss: dismiss)
                    }
                }
            } else {
                VStack(spacing: 3) {
                    ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                        BlitzSourcePickerRow(item: item, dismiss: dismiss)
                    }
                }
            }
        }
    }
}

private struct BlitzSourcePickerThumbnailCard: View {
    let item: BlitzSourcePickerItem
    let dismiss: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            item.action()
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                preview

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.94))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.46))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
            }
            .background(rowFill, in: .rect(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(item.isSelected ? BlitzUI.mint.opacity(0.7) : .white.opacity(0.08), lineWidth: 1)
            }
            .contentShape(.rect(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .pointingHandCursor()
    }

    private var preview: some View {
        ZStack {
            Color.black.opacity(0.44)

            if let thumbnail = item.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [.white.opacity(0.07), .white.opacity(0.025)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: item.systemImage)
                    .font(.system(size: 24, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.32))
            }

            VStack {
                HStack {
                    if let icon = item.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 22, height: 22)
                            .padding(4)
                            .background(.black.opacity(0.66), in: .rect(cornerRadius: 7))
                    }

                    Spacer(minLength: 0)

                    Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(item.isSelected ? BlitzUI.mint : .white.opacity(0.72))
                        .shadow(color: .black.opacity(0.7), radius: 3)
                }
                Spacer(minLength: 0)
            }
            .padding(7)
        }
        .frame(height: 108)
        .clipShape(.rect(topLeadingRadius: 9, topTrailingRadius: 9))
    }

    private var rowFill: Color {
        if item.isSelected {
            return BlitzUI.mint.opacity(0.12)
        }
        return isHovering ? Color.white.opacity(0.09) : Color.white.opacity(0.035)
    }
}

private struct BlitzSourcePickerRow: View {
    let item: BlitzSourcePickerItem
    let dismiss: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            item.action()
            dismiss()
        } label: {
            HStack(spacing: 10) {
                pickerIcon

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.46))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(item.isSelected ? BlitzUI.mint : .white.opacity(0.18))
            }
            .padding(.horizontal, 9)
            .frame(minHeight: 46)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowFill, in: .rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(item.isSelected ? BlitzUI.mint.opacity(0.3) : .clear, lineWidth: 1)
            }
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .pointingHandCursor()
    }

    private var rowFill: Color {
        if item.isSelected {
            return BlitzUI.mint.opacity(0.1)
        }
        return isHovering ? Color.white.opacity(0.08) : Color.white.opacity(0.025)
    }

    @ViewBuilder
    private var pickerIcon: some View {
        if let icon = item.icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
                .clipShape(.rect(cornerRadius: 5))
                .frame(width: 30, height: 30)
        } else {
            Image(systemName: item.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(item.isSelected ? BlitzUI.mint : .white.opacity(0.62))
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.045), in: .rect(cornerRadius: 7))
        }
    }
}

private struct BlitzSourcePickerActionRow: View {
    let item: BlitzSourcePickerItem
    let dismiss: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            item.action()
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(BlitzUI.mint)
                    .frame(width: 30, height: 30)
                    .background(BlitzUI.mint.opacity(0.1), in: .rect(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.46))
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 9)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovering ? Color.white.opacity(0.08) : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .pointingHandCursor()
    }
}

private struct BlitzGlassMenuList: View {
    let entries: [BlitzMenuEntry]
    let width: CGFloat
    let maxHeight: CGFloat
    let dismiss: () -> Void

    private var adaptiveWidth: CGFloat {
        let visibleWidth = NSScreen.main?.visibleFrame.width ?? width
        return min(width, max(220, visibleWidth - 32))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    switch entry {
                    case .item(let item):
                        BlitzGlassMenuRow(item: item, dismiss: dismiss)
                    case .divider:
                        Divider()
                            .overlay(BlitzUI.separator)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                    case .section(let title):
                        Text(title.uppercased())
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(0.6)
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            .padding(.bottom, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(6)
        }
        .scrollIndicators(.visible)
        .frame(width: adaptiveWidth)
        .frame(maxHeight: maxHeight)
    }
}

private struct BlitzGlassMenuRow: View {
    let item: BlitzMenuItem
    let dismiss: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            item.action()
            dismiss()
        } label: {
            HStack(spacing: 9) {
                if let icon = item.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                        .clipShape(.rect(cornerRadius: 4))
                } else {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(iconColor)
                        .frame(width: 18, height: 18)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(textColor)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let subtitle = item.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: 8)

                if item.isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(BlitzUI.mint)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovering ? Color.white.opacity(0.09) : .clear, in: .rect(cornerRadius: 7))
            .contentShape(.rect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .pointingHandCursor()
    }

    private var textColor: Color {
        item.isDestructive ? BlitzUI.warning : .white.opacity(0.9)
    }

    private var iconColor: Color {
        item.isDestructive ? BlitzUI.warning : .white.opacity(0.6)
    }
}

import AppKit
import SwiftUI

/// The Cameras tab of a multicam project. Each camera is one row holding everything about it: its picture, its
/// name, whether it is live, whether its sound plays and its number key. Below, the live shot's framing is shown as
/// the pictures it would make, so a choice looks like its result.
struct EditorCamerasInspector: View {
    struct ThumbnailRequest {
        let role: String
        /// Take seconds.
        let time: Double
    }

    struct Configuration {
        let program: MulticamProgram
        let playback: EditorPlaybackController
        /// The camera whose sound is being prepared, while it is.
        let soundSwitch: String?
        let isInteractive: Bool
        let thumbnail: (ThumbnailRequest) -> CGImage?
        let onCut: (MulticamShot) -> Void
        let onReframe: (MulticamShot.Framing) -> Void
        let onChangeTiles: (MulticamProgram.Tiles) -> Void
        let onUseSound: (String) -> Void
        let onRename: (CameraAngleRenameRequest) -> Void
    }

    let configuration: Configuration
    /// The camera being renamed, while its name is a text field.
    @State private var renaming: String?
    @State private var hovered: Int?

    private var program: MulticamProgram { configuration.program }

    var body: some View {
        let time = configuration.playback.currentTime
        let live = program.liveShot(at: time)
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(program.shots) { shot in row(.init(shot: shot, isLive: shot.shot == live, time: time)) }
                Text("Click a shot or press 1–\(program.shots.count) to cut at the playhead.")
                    .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                    .padding(.top, 2)
            }
            if let live {
                framing(.init(shot: live, framing: program.liveFraming(at: time), time: time))
            }
        }
        .disabled(!configuration.isInteractive)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Rows

    private struct Row {
        let shot: MulticamProgram.Shot
        let isLive: Bool
        let time: Double
    }

    private func row(_ row: Row) -> some View {
        HStack(spacing: 10) {
            picture(.init(shot: row.shot.shot, zoom: nil, time: row.time))
                .frame(width: 72, height: 40.5)
                .clipShape(.rect(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 1) {
                switch row.shot.shot {
                case .camera(let role):
                    EditorCameraNameField(configuration: .init(
                        role: role, title: row.shot.title, isEditing: renaming == role,
                        showsPencil: hovered == row.shot.key,
                        onStartEditing: { renaming = role },
                        onEndEditing: { if renaming == role { renaming = nil } },
                        onRename: configuration.onRename
                    ))
                case .sideBySide:
                    Text("Side by side").font(BlitzType.body).padding(.horizontal, 4)
                }
                subtitle(row)
                    .padding(.horizontal, 4)
            }
            Spacer(minLength: 4)
            accessory(row.shot.shot)
            Text("\(row.shot.key)")
                .font(BlitzType.footnote.monospacedDigit())
                .foregroundStyle(BlitzUI.secondaryText)
                .frame(width: 18, height: 18)
                .background(BlitzUI.quietFill, in: .rect(cornerRadius: 4))
                .help("Press \(row.shot.key) to cut to this shot")
        }
        .padding(6)
        .background(row.isLive ? BlitzUI.selectedFill : BlitzUI.cardFill, in: .rect(cornerRadius: BlitzUI.controlRadius))
        .overlay {
            RoundedRectangle(cornerRadius: BlitzUI.controlRadius)
                .strokeBorder(row.isLive ? BlitzUI.accent : .clear, lineWidth: 1.5)
        }
        .contentShape(.rect(cornerRadius: BlitzUI.controlRadius))
        .onHover { isHovering in
            if isHovering {
                hovered = row.shot.key
            } else if hovered == row.shot.key {
                hovered = nil
            }
        }
        .onTapGesture {
            renaming = nil
            configuration.onCut(row.shot.shot)
        }
        .contextMenu {
            if case .camera(let role) = row.shot.shot {
                Button("Rename…", systemImage: "pencil") { renaming = role }
            }
            tileMenu(row.shot.shot)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(row.shot.title)
        .accessibilityValue(row.isLive ? "On screen" : "")
        .accessibilityAction(named: "Cut to \(row.shot.title)") { configuration.onCut(row.shot.shot) }
        .help("Show \(row.shot.title) from the playhead")
    }

    @ViewBuilder
    private func subtitle(_ row: Row) -> some View {
        let angle: MulticamProgram.Angle? = if case .camera(let role) = row.shot.shot { program.angle(role: role) } else { nil }
        HStack(spacing: 6) {
            if row.isLive {
                Text("Live").font(BlitzType.footnote).foregroundStyle(BlitzUI.accent)
            }
            if let angle, angle.needsReview {
                Label("Check sync", systemImage: "exclamationmark.triangle")
                    .font(BlitzType.footnote).foregroundStyle(BlitzUI.warning)
                    .help(angle.syncStatusText)
            } else {
                Text(detail(row.shot.shot)).font(BlitzType.footnote).foregroundStyle(BlitzUI.secondaryText)
            }
        }
        .lineLimit(1)
    }

    /// How the importer read the shot: the wide shot sees everyone; a speaker's camera one face, seated left or
    /// right by where that person looks.
    private func detail(_ shot: MulticamShot) -> String {
        switch shot {
        case .sideBySide(let left, let right):
            return "\(program.angle(role: left)?.title ?? left) · \(program.angle(role: right)?.title ?? right)"
        case .camera(let role):
            guard let angle = program.angle(role: role) else { return "" }
            if angle.faceCount >= 2 { return "Wide · \(angle.faceCount) people" }
            guard angle.faceCount == 1 else { return "Camera" }
            switch role {
            case sideBySideTiles?.left: return "Speaker · sits left"
            case sideBySideTiles?.right: return "Speaker · sits right"
            default: return "Speaker"
            }
        }
    }

    private var sideBySideTiles: MulticamProgram.Tiles? {
        program.shots.lazy.compactMap { shot -> MulticamProgram.Tiles? in
            guard case .sideBySide(let left, let right) = shot.shot else { return nil }
            return .init(left: left, right: right)
        }.first
    }

    @ViewBuilder
    private func accessory(_ shot: MulticamShot) -> some View {
        switch shot {
        case .camera(let role):
            soundButton(role)
        case .sideBySide(let left, let right):
            Button { configuration.onChangeTiles(.init(left: right, right: left)) } label: {
                Image(systemName: "arrow.left.arrow.right").frame(width: 16, height: 16)
            }
            .blitzButton(.quiet)
            .controlSize(.small)
            .accessibilityLabel("Swap the two speakers")
            .help("Swap left and right. Right-click the row to pick other cameras.")
        }
    }

    private func soundButton(_ role: String) -> some View {
        let isSound = (configuration.soundSwitch ?? program.angles.first(where: \.isSound)?.role) == role
        let title = program.angle(role: role)?.title ?? role
        return Button { configuration.onUseSound(role) } label: {
            Group {
                if configuration.soundSwitch == role {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: isSound ? BlitzSymbols.systemAudio : "speaker")
                        .symbolVariant(isSound ? .fill : .none)
                        .foregroundStyle(isSound ? BlitzUI.primaryText : BlitzUI.tertiaryText)
                }
            }
            .frame(width: 16, height: 16)
        }
        .blitzButton(isSound ? .secondary : .quiet)
        .controlSize(.small)
        .disabled(configuration.soundSwitch != nil)
        .accessibilityLabel(isSound ? "Sound plays from \(title)" : "Play \(title)'s sound")
        .help(isSound ? "The video's sound comes from \(title). \(program.angle(role: role)?.syncStatusText ?? "")"
              : "Play \(title)'s sound instead. The other cameras stay silent.")
    }

    @ViewBuilder
    private func tileMenu(_ shot: MulticamShot) -> some View {
        if case .sideBySide(let left, let right) = shot {
            Menu("Left camera") {
                ForEach(program.angles) { angle in
                    Button(angle.title) { configuration.onChangeTiles(.init(left: angle.role, right: right)) }
                        .disabled(angle.role == left)
                }
            }
            Menu("Right camera") {
                ForEach(program.angles) { angle in
                    Button(angle.title) { configuration.onChangeTiles(.init(left: left, right: angle.role)) }
                        .disabled(angle.role == right)
                }
            }
        }
    }

    // MARK: Pictures

    private struct Picture {
        let shot: MulticamShot
        /// Nil shows a shot's cameras as the row thumbnails do; otherwise as framed at that closeness.
        let zoom: MulticamShot.Closeness?
        let time: Double
    }

    @ViewBuilder
    private func picture(_ picture: Picture) -> some View {
        switch picture.shot {
        case .camera(let role):
            MulticamThumbnail(configuration: .init(
                image: configuration.thumbnail(.init(role: role, time: picture.time)),
                face: program.face(role: role),
                zoom: zoom(.init(role: role, closeness: picture.zoom, tiled: false))
            ))
        case .sideBySide(let left, let right):
            HStack(spacing: 1.5) {
                ForEach([left, right], id: \.self) { role in
                    MulticamThumbnail(configuration: .init(
                        image: configuration.thumbnail(.init(role: role, time: picture.time)),
                        face: program.face(role: role),
                        zoom: zoom(.init(role: role, closeness: picture.zoom, tiled: true))
                    ))
                }
            }
            .background(BlitzUI.panelBackground)
        }
    }

    private struct ZoomRequest {
        let role: String
        let closeness: MulticamShot.Closeness?
        let tiled: Bool
    }

    /// How far a thumbnail crops in so it matches the closeness: the face fills the same share of the picture.
    private func zoom(_ request: ZoomRequest) -> CGFloat {
        guard let face = program.face(role: request.role), face.height > 0 else { return 1 }
        guard let closeness = request.closeness else { return request.tiled ? 1 : 1.3 }
        guard let faceHeight = closeness.faceHeight(tiled: request.tiled) else { return 1 }
        return max(1, faceHeight / face.height)
    }

    // MARK: Framing

    private struct FramingControls {
        let shot: MulticamShot
        /// Nil once the part was laid out or cropped by hand.
        let framing: MulticamShot.Framing?
        let time: Double
    }

    @ViewBuilder
    private func framing(_ controls: FramingControls) -> some View {
        let current = controls.framing ?? .standard(for: controls.shot)
        let framesFace: Bool = switch controls.shot {
        case .camera(let role): program.face(role: role) != nil
        case .sideBySide: true
        }
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Framing").font(BlitzType.section).foregroundStyle(BlitzUI.primaryText)
                Spacer()
                Text("This part").font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
            }
            if framesFace {
                HStack(spacing: 8) {
                    ForEach(MulticamShot.Closeness.allCases, id: \.self) { closeness in
                        let isSelected = controls.framing?.closeness == closeness
                        Button {
                            var framing = current; framing.closeness = closeness; configuration.onReframe(framing)
                        } label: {
                            VStack(spacing: 5) {
                                picture(.init(shot: controls.shot, zoom: closeness, time: controls.time))
                                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                                    .clipShape(.rect(cornerRadius: 5))
                                Text(closeness.title).font(BlitzType.caption)
                            }
                            .padding(5)
                        }
                        .buttonStyle(BlitzSelectionButtonStyle(isSelected: isSelected))
                        .accessibilityLabel(closeness.title)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .help("Frame the speakers \(closeness.title.lowercased()). Your next cuts keep it.")
                    }
                }
                if case .sideBySide = controls.shot {
                    gapPicker(current)
                }
                if controls.framing == nil {
                    Text("Laid out by hand. Pick a framing to line the speakers up again.")
                        .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                }
            } else {
                Text("The wide shot always shows the whole room.")
                    .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
            }
        }
    }

    /// Four drawings of the two tiles, each with its gap, so the choice shows the space it leaves.
    private func gapPicker(_ current: MulticamShot.Framing) -> some View {
        HStack(spacing: 8) {
            Text("Gap").font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                .frame(width: 30, alignment: .leading)
            ForEach(SceneTileSpacing.allCases, id: \.self) { spacing in
                let isSelected = current.spacing == spacing
                Button {
                    var framing = current; framing.spacing = spacing; configuration.onReframe(framing)
                } label: {
                    let gap = spacing.value * 40
                    HStack(spacing: gap) {
                        RoundedRectangle(cornerRadius: 1.5)
                        RoundedRectangle(cornerRadius: 1.5)
                    }
                    .padding(gap)
                    .foregroundStyle(isSelected ? BlitzUI.primaryText : BlitzUI.tertiaryText)
                    .frame(width: 40, height: 22)
                    .background(BlitzUI.panelBackground, in: .rect(cornerRadius: 3))
                    .padding(4)
                }
                .buttonStyle(BlitzSelectionButtonStyle(isSelected: isSelected))
                .accessibilityLabel("\(spacing.title) gap")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .help("\(spacing.title) gap around and between the speakers")
            }
            Spacer(minLength: 0)
        }
    }
}

/// A camera's picture filling its frame, centred on the face it frames when it frames one.
struct MulticamThumbnail: View {
    struct Configuration {
        let image: CGImage?
        /// Origin top left, as a fraction of the picture.
        let face: CGRect?
        /// 1 fills the frame; more crops in on the face.
        let zoom: CGFloat
    }

    let configuration: Configuration

    var body: some View {
        GeometryReader { proxy in
            if let image = configuration.image {
                let size = proxy.size
                let aspect = CGFloat(image.width) / CGFloat(max(image.height, 1))
                let fill = max(size.width / max(aspect, 0.0001), size.height) * configuration.zoom
                let picture = CGSize(width: fill * aspect, height: fill)
                let face = configuration.face ?? CGRect(x: 0.5, y: 0.42, width: 0, height: 0)
                let x = min(0, max(size.width - picture.width, size.width / 2 - face.midX * picture.width))
                let y = min(0, max(size.height - picture.height, size.height * 0.42 - face.midY * picture.height))
                Image(decorative: image, scale: 1)
                    .resizable()
                    .frame(width: picture.width, height: picture.height)
                    .offset(x: x, y: y)
            } else {
                BlitzUI.cardFill.overlay {
                    Image(systemName: BlitzSymbols.camera).foregroundStyle(BlitzUI.tertiaryText)
                }
            }
        }
        .background(BlitzUI.cardFill)
        .clipped()
        .accessibilityHidden(true)
    }
}

/// A camera's name: plain text, so a click on its row cuts to it. The pencil or Rename… turns it
/// into a field; Return or a click anywhere else saves it, Escape keeps the old name.
private struct EditorCameraNameField: View {
    struct Configuration {
        let role: String
        let title: String
        let isEditing: Bool
        let showsPencil: Bool
        let onStartEditing: () -> Void
        let onEndEditing: () -> Void
        let onRename: (CameraAngleRenameRequest) -> Void
    }

    let configuration: Configuration
    @State private var draft = ""
    @State private var fieldFrame: CGRect = .zero
    @State private var clickMonitor: Any?
    @State private var isCancelled = false
    @FocusState private var isFocused: Bool

    var body: some View {
        if configuration.isEditing {
            TextField("Camera name", text: $draft)
                .textFieldStyle(.plain)
                .font(BlitzType.body)
                .lineLimit(1)
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(BlitzUI.panelBackground, in: .rect(cornerRadius: 4))
                .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(BlitzUI.accent, lineWidth: 1) }
                .focused($isFocused)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { fieldFrame = $0 }
                .onSubmit(configuration.onEndEditing)
                .onExitCommand {
                    isCancelled = true
                    configuration.onEndEditing()
                }
                .onChange(of: isFocused) { _, focused in if !focused { configuration.onEndEditing() } }
                .onAppear(perform: begin)
                .onDisappear(perform: end)
                .accessibilityLabel("Name of \(configuration.title)")
        } else {
            HStack(spacing: 4) {
                Text(configuration.title)
                    .font(BlitzType.body)
                    .lineLimit(1).truncationMode(.middle)
                Button(action: configuration.onStartEditing) {
                    Image(systemName: "pencil")
                        .foregroundStyle(configuration.showsPencil ? BlitzUI.primaryText : BlitzUI.tertiaryText)
                        .frame(width: 12, height: 12)
                }
                .blitzButton(.quiet)
                .controlSize(.mini)
                .accessibilityLabel("Rename \(configuration.title)")
                .help("Rename this camera after who it films")
            }
            .padding(.horizontal, 4).padding(.vertical, 2)
        }
    }

    private func begin() {
        draft = configuration.title
        isCancelled = false
        isFocused = true
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            if let content = event.window?.contentView {
                let hit = content.hitTest(content.convert(event.locationInWindow, from: nil))
                let point = CGPoint(x: event.locationInWindow.x, y: content.bounds.height - event.locationInWindow.y)
                if !(hit is NSText || hit is NSTextField) && !fieldFrame.contains(point) {
                    configuration.onEndEditing()
                }
            }
            return event
        }
    }

    private func end() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isCancelled, !title.isEmpty, title != configuration.title else { return }
        configuration.onRename(.init(role: configuration.role, title: title))
    }
}

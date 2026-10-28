import AVFoundation
import IOKit
import SwiftUI

/// Studio inputs, laid out like a settings form: each input is a label over a dropdown that names the device.
/// A source is recorded when a device is chosen. There are no on/off switches: "No camera" sits in the menu,
/// and audio has Mute.
struct SourcesSidebar: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ScreenInputBlock(vm: vm)
                CameraInputBlock(vm: vm)
                MicrophoneInputBlock(vm: vm)
                SystemAudioInputBlock(vm: vm)
            }
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.automatic)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(BlitzMaterialBackground(kind: .sidebar))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inputs")
    }
}

// MARK: - Building blocks

/// The label above an input's dropdown, with its text actions (Add, Mute) on the right.
struct InputBlockHeader<Trailing: View>: View {
    let title: String
    /// Live, starting or needing a fix. No dot while the input is off.
    let status: BlitzStatusTone?
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(BlitzType.section)
                .foregroundStyle(BlitzUI.primaryText)
                .lineLimit(1)
            if let status {
                BlitzStatusDot(tone: status, diameter: 6)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 4)
            trailing()
        }
        .frame(height: 22)
    }
}

/// A small text action in an input header, such as Add or Mute.
struct InputHeaderAction: View {
    struct Configuration {
        let title: String
        let help: String
        let isEnabled: Bool
        let action: () -> Void
    }

    let configuration: Configuration

    var body: some View {
        Button(configuration.title, action: configuration.action)
            .blitzButton(.quiet)
            .controlSize(.small)
            .disabled(!configuration.isEnabled)
            .help(configuration.help)
    }
}

/// A dropdown that names the chosen device. Clicking it opens the picker the caller attaches.
/// How a field shows its value: a chosen device, an empty choice, or a problem.
enum InputFieldTone { case value, placeholder, warning }

struct InputField<Leading: View>: View {

    struct Configuration {
        let value: String
        /// Which track this device records, such as "Camera 2", shown above the field when there is more than one.
        let track: String?
        let tone: InputFieldTone
        let isEnabled: Bool
        let help: String
        let open: () -> Void
        let isPresented: Bool
    }

    let configuration: Configuration
    @ViewBuilder let leading: () -> Leading

    private var valueColor: Color {
        switch configuration.tone {
        case .value: BlitzUI.primaryText
        case .placeholder: BlitzUI.secondaryText
        case .warning: BlitzUI.warning
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let track = configuration.track {
                Text(track)
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .padding(.leading, 2)
            }
            field
        }
    }

    private var field: some View {
        Button(action: configuration.open) {
            HStack(spacing: 9) {
                leading()
                    .frame(width: InputFieldSlot.size.width, height: InputFieldSlot.size.height)
                    .background(BlitzUI.quietFill, in: .rect(cornerRadius: InputFieldSlot.radius, style: .continuous))
                    .clipShape(.rect(cornerRadius: InputFieldSlot.radius, style: .continuous))
                Text(configuration.value)
                    .font(BlitzType.navigation)
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(BlitzType.glyph(9))
                    .foregroundStyle(BlitzUI.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.leading, 5)
            .padding(.trailing, 10)
            .frame(height: 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(BlitzMenuTriggerStyle(isPresented: configuration.isPresented))
        .disabled(!configuration.isEnabled)
        .help(configuration.help)
        .accessibilityValue(configuration.value)
    }
}

/// The picture slot at the leading edge of every field: a live or still frame, or the device's symbol.
enum InputFieldSlot {
    static let size = CGSize(width: 40, height: 26)
    static let radius: CGFloat = BlitzUI.controlRadius / 2
}

/// A still frame of the screen source being recorded, refreshed when the source changes.
private struct ScreenSourceThumbnail: View {
    let binding: ScreenSourceBinding
    @Bindable var vm: RecorderViewModel
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                InputFieldSymbol(name: BlitzSymbols.screen)
            }
        }
        .task(id: binding.runtimeID) {
            image = await vm.screenSourceThumbnail(binding)
        }
    }
}

/// A device's symbol at the leading edge of its field.
private struct InputFieldSymbol: View {
    let name: String

    var body: some View {
        Image(systemName: name)
            .font(BlitzType.symbol(12))
            .foregroundStyle(BlitzUI.secondaryText)
            .accessibilityHidden(true)
    }
}

/// One problem under the field it concerns, with its fix.
private struct InputProblem: View {
    let notice: SourceReadinessNotice
    @Bindable var vm: RecorderViewModel

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if notice.isWaiting {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(BlitzType.glyph(10))
                        .foregroundStyle(notice.color)
                }
            }
            .frame(width: 14)
            .accessibilityHidden(true)
            Text(notice.title)
                .font(BlitzType.caption)
                .foregroundStyle(notice.isWaiting ? BlitzUI.secondaryText : BlitzUI.supportingText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let action = notice.action {
                Button(action.shortTitle) { vm.resolveSourceReadiness(action) }
                    .blitzButton(.secondary)
                    .controlSize(.small)
                    .disabled(vm.isRequestingPermissions)
                    .help(action.title)
            }
        }
        .help(notice.detail)
        .accessibilityElement(children: .combine)
    }
}

/// A plain line of secondary text under a field, such as "Hidden in this scene".
private struct InputNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(BlitzType.caption)
            .foregroundStyle(BlitzUI.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension RecorderViewModel {
    /// Choosing a device for a source that is off turns the source on.
    func turnOnSource(_ source: CaptureSource) {
        guard !isSourceConfigured(source) else { return }
        toggleSource(source)
    }

    /// Why the chosen iPhone camera is not sending video yet, if it is not.
    var remoteCameraWaitingNote: String? {
        guard isRemoteCameraSelected else { return nil }
        if selectedRemoteCameraConnectionState == .pairing { return "Tap Connect on the iPhone." }
        let status = (selectedRemoteCameraStatus ?? selectedRemoteCameraReviewStatus).lowercased()
        if status.contains("waiting") || status.contains("disconnect") || status.contains("unavailable") {
            return "Waiting for the iPhone. Open BlitzRecorder Camera on it."
        }
        return nil
    }

    /// The dot next to an input's name: ready, starting, or needing a fix; none while it is off.
    func inputStatus(_ source: CaptureSource) -> BlitzStatusTone? {
        guard isSourceConfigured(source) else { return nil }
        if source == .camera, !isRemoteCameraSelected, localCameraOptions.isEmpty { return .warning }
        if let notice = sourceReadinessNotice(source) { return notice.isWaiting ? .muted : .warning }
        if source == .screen, !hasActiveScreenPickerSelection { return .warning }
        return .ready
    }

    func sceneVisibilityNote(_ source: CaptureSource) -> String? {
        guard state == .idle, isSourceConfigured(source), !isSourceVisible(source) else { return nil }
        return "Hidden in \(selectedSceneName). Still recorded on its own track."
    }
}

// MARK: - Screen

private struct ScreenInputBlock: View {
    @Bindable var vm: RecorderViewModel

    private var isOn: Bool { vm.isSourceConfigured(.screen) }
    private var picker: BlitzSourcePickerModel { ScreenCaptureSourcePickerModel(vm: vm, enabled: true).model }

    private var value: (text: String, tone: InputFieldTone) {
        guard isOn else { return ("No screen", .placeholder) }
        guard vm.hasActiveScreenPickerSelection else { return ("Choose a screen", .placeholder) }
        let name = vm.selectedScreenSourceDisplayName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? ("Window closed", .warning) : (name, .value)
    }

    /// The missing pick already shows in the field, so only other problems get a line.
    private var problem: SourceReadinessNotice? {
        guard let notice = vm.sourceReadinessNotice(.screen), notice.action != .chooseScreen else { return nil }
        return notice
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            InputBlockHeader(title: "Screen", status: vm.inputStatus(.screen)) { EmptyView() }
            InputField(configuration: .init(
                value: value.text,
                track: nil,
                tone: value.tone,
                isEnabled: vm.canAdjustScreenCapture,
                help: "Choose a display, window or app to record",
                open: open,
                isPresented: vm.showsScreenSourcePicker
            )) {
                if isOn, vm.hasActiveScreenPickerSelection, !vm.settings.usesPickedScreenContent,
                   let binding = vm.settings.screenSourceBinding {
                    ScreenSourceThumbnail(binding: binding, vm: vm)
                } else {
                    InputFieldSymbol(name: BlitzSymbols.screen)
                }
            }
            .accessibilityLabel("Screen")
            .popover(isPresented: $vm.showsScreenSourcePicker, arrowEdge: .trailing) {
                BlitzSourcePickerPopover(model: picker) { vm.showsScreenSourcePicker = false }
            }
            if let problem {
                InputProblem(notice: problem, vm: vm)
            }
            if let note = vm.sceneVisibilityNote(.screen) {
                InputNote(text: note)
            }
        }
    }

    private func open() {
        guard isOn else { return vm.toggleSource(.screen) }
        vm.showsScreenSourcePicker = true
    }
}

// MARK: - Camera

private struct CameraInputBlock: View {
    @Bindable var vm: RecorderViewModel
    @State private var showsPicker = false
    @State private var dismissedIPhoneSuggestions: Set<String> = []

    private var isOn: Bool { vm.isSourceConfigured(.camera) }
    private var hasAngles: Bool { !vm.cameraAngles.isEmpty }
    private var hasAnyCamera: Bool { !vm.localCameraOptions.isEmpty || !vm.remoteCameraOptions.isEmpty }

    /// A BlitzRecorder Camera iPhone that is open nearby while another camera is chosen, often Continuity Camera.
    private var suggestedIPhone: SourceOption? {
        guard vm.state == .idle, isOn, !vm.isRemoteCameraSelected else { return nil }
        return vm.remoteCameraOptions.first { !dismissedIPhoneSuggestions.contains($0.id) }
    }

    private var symbol: String {
        if vm.isRemoteCameraSelected { return "iphone.gen3" }
        let selected = vm.localCameraOptions.first { $0.id == vm.settings.selectedCameraID }
        return selected?.cameraKind?.systemImage ?? BlitzSymbols.camera
    }

    private var value: (text: String, tone: InputFieldTone) {
        guard isOn else { return ("No camera", .placeholder) }
        if !vm.isRemoteCameraSelected, vm.localCameraOptions.isEmpty { return ("No camera connected", .placeholder) }
        if !vm.isRemoteCameraSelected, vm.settings.selectedCameraID == nil, let name = vm.systemDefaultCameraName {
            return (name, .value)
        }
        return (vm.selectedCameraDisplayName, .value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            InputBlockHeader(title: hasAngles ? "Cameras" : "Camera", status: vm.inputStatus(.camera)) { EmptyView() }
            InputField(configuration: .init(
                value: value.text,
                track: hasAngles ? vm.mainCameraTitle : nil,
                tone: value.tone,
                isEnabled: vm.state == .idle,
                help: "Choose the camera to record",
                open: { showsPicker = true },
                isPresented: showsPicker
            )) {
                InputFieldSymbol(name: symbol)
            }
            .accessibilityLabel(vm.mainCameraTitle)
            .popover(isPresented: $showsPicker, arrowEdge: .trailing) {
                CameraPickerPopover(vm: vm) { showsPicker = false }
            }
            .onChange(of: vm.state) { if vm.state != .idle { showsPicker = false } }

            if !hasAnyCamera, isOn {
                InputNote(text: "Plug in a camera, or use your iPhone with BlitzRecorder Camera.")
            } else if let notice = vm.sourceReadinessNotice(.camera) {
                InputProblem(notice: notice, vm: vm)
            } else if let note = vm.remoteCameraWaitingNote {
                InputNote(text: note)
            }
            if let note = vm.sceneVisibilityNote(.camera) {
                InputNote(text: note)
            }
            if let iPhone = suggestedIPhone {
                IPhoneCameraSuggestion(configuration: .init(
                    name: iPhone.name,
                    replacesContinuity: vm.selectedContinuityCamera != nil,
                    use: { vm.setCamera(iPhone.id) },
                    dismiss: { dismissedIPhoneSuggestions.insert(iPhone.id) }
                ))
                .transition(.opacity)
            }
            CameraAnglesSection(vm: vm)
            CameraAngleAddButton(vm: vm)
        }
    }
}

extension RecorderViewModel {
    /// The camera macOS picks when BlitzRecorder follows the system default.
    var systemDefaultCameraName: String? {
        AVCaptureDevice.default(for: .video).map { CameraOptionName.plain($0.localizedName) }
    }
}

/// The camera dropdown: every connected camera by name and kind, a check on the one in use, and a visible
/// "Add angle" on the others. With no camera at all it says so and offers the iPhone.
struct CameraPickerPopover: View {
    @Bindable var vm: RecorderViewModel
    let dismiss: () -> Void
    @State private var camerasInDriveMode: [String] = []

    private var isOn: Bool { vm.isSourceConfigured(.camera) }
    private var local: [SourceOption] { vm.localCameraOptions.filter { $0.cameraKind != .deskView } }
    private var deskViews: [SourceOption] { vm.localCameraOptions.filter { $0.cameraKind == .deskView } }
    private var mainDeviceID: String? { vm.coordinator.mainLocalCameraDeviceID }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Camera")
                    .font(BlitzType.headline)
                    .foregroundStyle(BlitzUI.primaryText)
                Spacer()
                Button {
                    vm.startRemoteCameraDiscovery()
                    Task { await vm.refreshSources() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .blitzButton(.quiet)
                .controlSize(.small)
                .help("Look for cameras again")
                .accessibilityLabel("Look for cameras again")
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ForEach(camerasInDriveMode, id: \.self) { name in
                driveModeNote(name)
            }
            if local.isEmpty && vm.remoteCameraOptions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        if !local.isEmpty {
                            sectionTitle("Connected cameras")
                            ForEach(local, id: \.id) { option in localRow(option) }
                        }
                        sectionTitle("Wireless iPhone · BlitzRecorder Camera")
                        ForEach(vm.remoteCameraOptions, id: \.id) { option in remoteRow(option) }
                        iPhoneSetupRow
                        if !deskViews.isEmpty {
                            sectionTitle("Desk View")
                            ForEach(deskViews, id: \.id) { option in localRow(option) }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .frame(maxHeight: 420)
                .fixedSize(horizontal: false, vertical: true)
                footer
            }
        }
        .frame(width: 340)
        .background(BlitzUI.panelBackground)
        .task {
            vm.startRemoteCameraDiscovery()
            camerasInDriveMode = USBCameraMode.camerasNotInWebcamMode()
        }
    }

    private func driveModeNote(_ name: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(BlitzType.glyph(12))
                .foregroundStyle(BlitzUI.warning)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(name) is plugged in as a drive")
                    .font(BlitzType.navigation)
                    .foregroundStyle(BlitzUI.primaryText)
                Text("On the camera, choose Webcam mode. It shows up here a few seconds later.")
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BlitzUI.warning.opacity(0.1), in: .rect(cornerRadius: BlitzUI.controlRadius, style: .continuous))
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "video.slash")
                    .font(BlitzType.glyph(20))
                    .foregroundStyle(BlitzUI.secondaryText)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text("No camera connected")
                        .font(BlitzType.section)
                        .foregroundStyle(BlitzUI.primaryText)
                    Text("Plug in a USB camera, or turn your iPhone into a 4K camera with the free BlitzRecorder Camera app.")
                        .font(BlitzType.caption)
                        .foregroundStyle(BlitzUI.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                Button("Use my iPhone") {
                    dismiss()
                    vm.showSettings(.devices)
                }
                .blitzButton(.accent)
                if isOn {
                    Button("Record without a camera") {
                        dismiss()
                        vm.removeSource(.camera)
                    }
                    .blitzButton(.quiet)
                }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    private func sectionTitle(_ title: String) -> some View {
        BlitzUI.sectionLabel(title)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func localRow(_ option: SourceOption) -> some View {
        let kind = option.cameraKind ?? .external
        let isMain = isOn && !vm.isRemoteCameraSelected
            && (vm.settings.selectedCameraID == option.id
                || (vm.settings.selectedCameraID == nil && option.id == mainDeviceID))
        let angle = vm.cameraAngles.first { $0.deviceID == option.id }
        let canBeAngle = isOn && !isMain && kind != .deskView && vm.state == .idle
        return CameraPickerRow(configuration: .init(
            symbol: kind.systemImage,
            title: CameraOptionName.plain(option.name),
            detail: angle.map { "Recording as \($0.name)" } ?? kind.subtitle,
            isSelected: isMain,
            select: {
                dismiss()
                vm.setCamera(option.id)
                vm.turnOnSource(.camera)
            }
        )) {
            if let angle {
                Button("Remove") { vm.removeCameraAngle(angle.deviceID) }
                    .blitzButton(.quiet)
                    .controlSize(.small)
                    .help("Stop recording \(angle.name)")
            } else if canBeAngle {
                Button("Add angle") { vm.addCameraAngle(option.id) }
                    .blitzButton(.secondary)
                    .controlSize(.small)
                    .help("Record this camera too, as a second angle")
            }
        }
    }

    private func remoteRow(_ option: SourceOption) -> some View {
        CameraPickerRow(configuration: .init(
            symbol: "iphone.gen3",
            title: option.name,
            detail: "BlitzRecorder Camera · up to 4K",
            isSelected: isOn && vm.settings.selectedCameraID == option.id,
            select: {
                dismiss()
                vm.setCamera(option.id)
                vm.turnOnSource(.camera)
            }
        )) { EmptyView() }
    }

    private var iPhoneSetupRow: some View {
        CameraPickerRow(configuration: .init(
            symbol: "iphone.radiowaves.left.and.right",
            title: vm.remoteCameraOptions.isEmpty ? "Use your iPhone as a camera" : "Connect another iPhone",
            detail: "Open BlitzRecorder Camera on the iPhone",
            isSelected: false,
            select: {
                dismiss()
                vm.showSettings(.devices)
            }
        )) { EmptyView() }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !local.isEmpty {
                CameraPickerRow(configuration: .init(
                    symbol: "macbook.and.iphone",
                    title: "Follow the macOS default",
                    detail: vm.systemDefaultCameraName.map { "Now \($0)" } ?? "Whatever camera macOS picks",
                    isSelected: isOn && !vm.isRemoteCameraSelected && vm.settings.selectedCameraID == nil,
                    select: {
                        dismiss()
                        vm.setCamera(nil)
                        vm.turnOnSource(.camera)
                    }
                )) { EmptyView() }
            }
            if isOn {
                CameraPickerRow(configuration: .init(
                    symbol: "video.slash",
                    title: "No camera",
                    detail: "Record the screen only",
                    isSelected: false,
                    select: {
                        dismiss()
                        vm.removeSource(.camera)
                    }
                )) { EmptyView() }
            }
        }
        .padding(8)
        .background(BlitzUI.quietFill)
    }
}

/// Action cameras (DJI Osmo, Action) plugged in by USB but in storage mode: macOS sees a drive, not a camera.
enum USBCameraMode {
    private static let cameraVendorIDs: Set<Int> = [0x2CA3]
    private static let videoInterfaceClass = 14

    static func camerasNotInWebcamMode() -> [String] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator)
                == KERN_SUCCESS else { return [] }
        var names: [String] = []
        var device = IOIteratorNext(iterator)
        while device != 0 {
            if let vendor = property(device, "idVendor") as? Int, cameraVendorIDs.contains(vendor),
               !hasVideoInterface(device),
               let product = property(device, "USB Product Name") as? String {
                names.append(friendlyName(product))
            }
            IOObjectRelease(device)
            device = IOIteratorNext(iterator)
        }
        IOObjectRelease(iterator)
        return names
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func hasVideoInterface(_ device: io_registry_entry_t) -> Bool {
        var children: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(device, kIOServicePlane, &children) == KERN_SUCCESS else { return false }
        var found = false
        var child = IOIteratorNext(children)
        while child != 0 {
            if property(child, "bInterfaceClass") as? Int == videoInterfaceClass { found = true }
            IOObjectRelease(child)
            child = IOIteratorNext(children)
        }
        IOObjectRelease(children)
        return found
    }

    /// "OsmoPocket4-ANGZP3U002J01R" → "Osmo Pocket 4".
    private static func friendlyName(_ product: String) -> String {
        let model = product.split(separator: "-").first.map(String.init) ?? product
        return model.replacingOccurrences(of: "([a-z])([A-Z0-9])", with: "$1 $2", options: .regularExpression)
    }
}

private struct CameraPickerRow<Accessory: View>: View {
    struct Configuration {
        let symbol: String
        let title: String
        let detail: String
        let isSelected: Bool
        let select: () -> Void
    }

    let configuration: Configuration
    @ViewBuilder let accessory: () -> Accessory
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: configuration.select) {
                HStack(spacing: 10) {
                    Image(systemName: configuration.symbol)
                        .font(BlitzType.symbol(14))
                        .foregroundStyle(configuration.isSelected ? BlitzUI.accent : BlitzUI.secondaryText)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(configuration.title)
                            .font(BlitzType.navigation)
                            .foregroundStyle(BlitzUI.primaryText)
                        Text(configuration.detail)
                            .font(BlitzType.caption)
                            .foregroundStyle(BlitzUI.secondaryText)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 4)
                    if configuration.isSelected {
                        Image(systemName: "checkmark")
                            .font(BlitzType.glyph(11))
                            .foregroundStyle(BlitzUI.accent)
                            .accessibilityLabel("In use")
                    }
                }
                .frame(height: 42)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(configuration.isSelected ? .isSelected : [])
            accessory()
        }
        .padding(.horizontal, 8)
        .background {
            RoundedRectangle(cornerRadius: BlitzUI.controlRadius, style: .continuous)
                .fill(isHovering ? BlitzUI.quietFill : .clear)
        }
        .onHover { isHovering = $0 }
    }
}

// MARK: - Audio

/// The live level inside a volume slider, with the volume in percent next to it.
private struct VolumeRow: View {
    struct Configuration {
        let title: String
        let levels: TrackLevels
        let active: Bool
        let gain: Binding<Double>
        let isEnabled: Bool
    }

    let configuration: Configuration

    var body: some View {
        HStack(spacing: 8) {
            BlitzMeterFader(configuration: .init(
                title: configuration.title,
                levels: configuration.levels,
                active: configuration.active,
                gain: configuration.gain,
                isEnabled: configuration.isEnabled
            ))
            Text("\(Int((configuration.gain.wrappedValue * 100).rounded()))%")
                .font(BlitzType.numeric)
                .foregroundStyle(BlitzUI.secondaryText)
                .frame(width: 36, alignment: .trailing)
        }
    }
}

private struct MicrophoneInputBlock: View {
    @Bindable var vm: RecorderViewModel
    @State private var showsPicker = false

    private var isOn: Bool { vm.isSourceConfigured(.microphone) }
    private var hasTracks: Bool { !vm.microphoneTracks.isEmpty }
    private var picker: BlitzSourcePickerModel { MicrophoneSourcePickerModel(vm: vm, enabled: true).model }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            InputBlockHeader(title: hasTracks ? "Microphones" : "Microphone", status: vm.inputStatus(.microphone)) {
                MicrophoneTrackAddButton(vm: vm)
                InputHeaderAction(configuration: .init(
                    title: isOn ? "Mute" : "Unmute",
                    help: isOn ? "Don't record your microphone" : "Record your microphone",
                    isEnabled: vm.state == .idle,
                    action: { vm.toggleSource(.microphone) }
                ))
            }
            InputField(configuration: .init(
                value: vm.selectedMicrophoneDisplayName,
                track: hasTracks ? vm.mainMicrophoneTitle : nil,
                tone: isOn ? .value : .placeholder,
                isEnabled: picker.enabled,
                help: "Choose the microphone to record",
                open: { showsPicker = true },
                isPresented: showsPicker
            )) {
                InputFieldSymbol(name: BlitzSymbols.microphone)
            }
            .accessibilityLabel(vm.mainMicrophoneTitle)
            .popover(isPresented: $showsPicker, arrowEdge: .trailing) {
                BlitzSourcePickerPopover(model: picker) { showsPicker = false }
            }

            if isOn {
                VolumeRow(configuration: .init(
                    title: "\(vm.mainMicrophoneTitle) volume",
                    levels: vm.micLevels,
                    active: vm.sourceReadinessNotice(.microphone) == nil,
                    gain: Binding(get: { vm.settings.microphoneGain }, set: { vm.setMicrophoneGain($0) }),
                    isEnabled: vm.state == .idle
                ))
                if let notice = vm.sourceReadinessNotice(.microphone) {
                    InputProblem(notice: notice, vm: vm)
                }
            } else {
                InputNote(text: "Muted · your voice isn't recorded")
            }
            MicrophoneTracksSection(vm: vm)
        }
    }
}

private struct SystemAudioInputBlock: View {
    @Bindable var vm: RecorderViewModel

    private var isOn: Bool { vm.isSourceConfigured(.systemAudio) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            InputBlockHeader(title: "Mac audio", status: vm.inputStatus(.systemAudio)) {
                InputHeaderAction(configuration: .init(
                    title: isOn ? "Mute" : "Unmute",
                    help: isOn ? "Don't record sound from your apps" : "Record sound from your apps",
                    isEnabled: vm.state == .idle,
                    action: { vm.toggleSource(.systemAudio) }
                ))
            }
            if isOn {
                VolumeRow(configuration: .init(
                    title: "Mac audio volume",
                    levels: vm.sysLevels,
                    active: vm.sourceReadinessNotice(.systemAudio) == nil,
                    gain: Binding(get: { vm.settings.systemAudioGain }, set: { vm.setSystemAudioGain($0) }),
                    isEnabled: vm.state == .idle
                ))
                if let notice = vm.sourceReadinessNotice(.systemAudio) {
                    InputProblem(notice: notice, vm: vm)
                }
            } else {
                InputNote(text: "Muted · app sound isn't recorded")
            }
        }
    }
}

/// A live waveform that is also the volume fader: the bars show the level, the handle sets the volume, and the
/// track past the handle dims. 100% sits in the middle; double-click resets it.
struct BlitzMeterFader: View {
    struct Configuration {
        let title: String
        let levels: TrackLevels
        let active: Bool
        let gain: Binding<Double>
        let isEnabled: Bool
    }

    private static let range = 0.0...2.0
    private static let height: CGFloat = 24

    let configuration: Configuration
    @State private var isHovering = false

    private var gain: Double { configuration.gain.wrappedValue }
    private var percent: Int { Int((gain * 100).rounded()) }

    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            let fraction = CGFloat(min(1, max(0, (gain - Self.range.lowerBound) / (Self.range.upperBound - Self.range.lowerBound))))
            let handleX = fraction * width
            let shape = RoundedRectangle(cornerRadius: InputFieldSlot.radius, style: .continuous)
            ZStack(alignment: .leading) {
                shape.fill(BlitzUI.insetWell)
                BlitzLevelMeter(levels: configuration.levels, active: configuration.active)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 5)
                Rectangle()
                    .fill(BlitzUI.panelBackground.opacity(0.6))
                    .frame(width: max(0, width - handleX))
                    .offset(x: handleX)
                Capsule()
                    .fill(BlitzUI.primaryText)
                    .frame(width: 3, height: Self.height - 6)
                    .shadow(color: BlitzUI.elevationShadow, radius: 2, y: 1)
                    .offset(x: min(max(1, handleX - 1.5), width - 4))
                    .opacity(configuration.isEnabled ? (isHovering ? 1 : 0.85) : 0.35)
            }
            .clipShape(shape)
            .contentShape(shape)
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard configuration.isEnabled else { return }
                set(fraction: value.location.x / width)
            })
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                if configuration.isEnabled { configuration.gain.wrappedValue = 1 }
            })
            .onHover { isHovering = $0 }
        }
        .frame(height: Self.height)
        .help(configuration.isEnabled
              ? "Volume \(percent)%. Drag to change, double-click for 100%."
              : "Volume \(percent)%. Change it after this recording.")
        .accessibilityElement()
        .accessibilityLabel(configuration.title)
        .accessibilityValue("\(percent) percent")
        .accessibilityAdjustableAction { direction in
            guard configuration.isEnabled else { return }
            switch direction {
            case .increment: configuration.gain.wrappedValue = min(Self.range.upperBound, gain + 0.05)
            case .decrement: configuration.gain.wrappedValue = max(Self.range.lowerBound, gain - 0.05)
            @unknown default: break
            }
        }
    }

    private func set(fraction: Double) {
        let clamped = min(1, max(0, fraction))
        var value = Self.range.lowerBound + clamped * (Self.range.upperBound - Self.range.lowerBound)
        if abs(value - 1) < 0.04 { value = 1 }
        configuration.gain.wrappedValue = (value * 100).rounded() / 100
    }
}

/// One click from Continuity Camera (or any camera) to the iPhone running BlitzRecorder Camera.
private struct IPhoneCameraSuggestion: View {
    struct Configuration {
        let name: String
        let replacesContinuity: Bool
        let use: () -> Void
        let dismiss: () -> Void
    }

    let configuration: Configuration

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "iphone.gen3")
                    .font(BlitzType.glyph(11))
                    .foregroundStyle(BlitzUI.accent)
                    .accessibilityHidden(true)
                Text("\(configuration.name) is open in BlitzRecorder Camera")
                    .font(BlitzType.captionEmphasis)
                    .foregroundStyle(BlitzUI.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(configuration.replacesContinuity
                 ? "Better quality than Continuity Camera. Continuity turns off when you switch."
                 : "Record in 4K with full camera controls.")
                .font(BlitzType.caption)
                .foregroundStyle(BlitzUI.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Button("Use iPhone", action: configuration.use)
                    .blitzButton(.accent)
                Button("Not now", action: configuration.dismiss)
                    .blitzButton(.quiet)
            }
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { BlitzSelectedBackground(cornerRadius: BlitzUI.cardRadius) }
        .padding(.vertical, 4)
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

#Preview("Sources - Camera angles") {
    SourcesSidebar(vm: SourcesSidebarPreviewFactory.cameraAngles())
        .frame(width: 260, height: 780)
        .padding()
}

#Preview("Sources - Preferred mic missing") {
    SourcesSidebar(vm: SourcesSidebarPreviewFactory.preferredMicMissing())
        .frame(height: 780)
        .padding()
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
        vm.selectSource(.screen)
        return vm
    }

    static func cameraSelected() -> RecorderViewModel {
        var settings = previewSettings
        settings.selectedScenePreset = .cameraInset
        settings.selectedCameraID = "preview-camera"
        let vm = makeViewModel(settings: settings)
        vm.selectSource(.camera)
        return vm
    }

    static func cameraAngles() -> RecorderViewModel {
        var settings = previewSettings
        settings.selectedScenePreset = .cameraInset
        settings.selectedCameraID = "preview-camera"
        settings.extraCameraAngleIDs = ["preview-usb", "preview-unplugged"]
        let vm = makeViewModel(settings: settings)
        vm.availableCameras += [
            SourceOption(id: "preview-usb", name: "Osmo Pocket 3", cameraKind: .external),
            SourceOption(id: "preview-iphone", name: "iPhone (Continuity)", cameraKind: .continuity)
        ]
        vm.selectSource(.camera)
        return vm
    }

    static func micSelected() -> RecorderViewModel {
        var settings = previewSettings
        settings.enabledSources = [.screen, .camera, .microphone]
        settings.hiddenSources = [.camera]
        settings.selectedMicrophoneID = "preview-mic"
        let vm = makeViewModel(settings: settings)
        vm.selectSource(.microphone)
        return vm
    }

    static func preferredMicMissing() -> RecorderViewModel {
        var settings = previewSettings
        settings.enabledSources = [.screen, .camera, .microphone]
        settings.hiddenSources = [.camera]
        settings.selectedMicrophoneID = "preview-rodecaster"
        settings.selectedMicrophoneName = "RODECaster Pro II Chat"
        let vm = makeViewModel(settings: settings)
        vm.selectSource(.microphone)
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
        vm.screenSource.targetWindowInfo = TargetWindowInfo(
            appName: "Safari",
            windowTitle: "Landing Page",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )
        vm.screenSource.targetWindowStatus = "Safari - Landing Page"
        previewLevels.forEach { vm.micLevels.append($0) }
        previewLevels.reversed().forEach { vm.sysLevels.append($0) }
        return vm
    }

    private static var previewLevels: [Float] {
        [0.12, 0.28, 0.42, 0.22, 0.68, 0.38, 0.52, 0.31, 0.74, 0.49, 0.26, 0.58]
    }
}
#endif

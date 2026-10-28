import SwiftUI

/// Extra microphones under the Microphone row. Every microphone records its own file, and the take's
/// microphone track is their mix.
struct MicrophoneTracksSection: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        if !vm.microphoneTracks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(vm.microphoneTracks) { track in
                    MicrophoneTrackRow(track: track, vm: vm)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("All microphones are mixed into one track. Each one also saves on its own.")
        }
    }
}

/// The + next to Audio: record another microphone at the same time.
struct MicrophoneTrackAddButton: View {
    @Bindable var vm: RecorderViewModel
    @State private var showsPicker = false

    var body: some View {
        if vm.isSourceConfigured(.microphone), !vm.microphoneTrackCandidates.isEmpty {
            Button("Add") { showsPicker = true }
            .blitzButton(.quiet)
            .controlSize(.small)
            .disabled(vm.state != .idle)
            .help(vm.state == .idle ? "Record another microphone at the same time, on its own track" : "Microphones are locked while recording")
            .accessibilityLabel("Add microphone")
            .popover(isPresented: $showsPicker, arrowEdge: .trailing) {
                BlitzSourcePickerPopover(model: MicrophoneTrackPickerModel.add(vm: vm)) { showsPicker = false }
            }
            .onChange(of: vm.state) { if vm.state != .idle { showsPicker = false } }
        }
    }
}

private struct MicrophoneTrackRow: View {
    let track: MicrophoneTrackItem
    @Bindable var vm: RecorderViewModel
    @State private var showsPicker = false

    private var isLocked: Bool { vm.state != .idle }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            InputField(configuration: .init(
                value: track.deviceName,
                track: track.name,
                tone: track.isConnected ? .value : .warning,
                isEnabled: !isLocked,
                help: isLocked ? "\(track.name) is recording" : "Change or remove \(track.name)",
                open: { showsPicker = true },
                isPresented: showsPicker
            )) {
                Image(systemName: BlitzSymbols.microphone)
                    .font(BlitzType.symbol(12))
                    .foregroundStyle(BlitzUI.secondaryText)
                    .accessibilityHidden(true)
            }
            .accessibilityLabel(track.name)
            .contextMenu {
                BlitzContextMenuItems(entries: [.item(BlitzMenuItem(
                    title: "Remove \(track.name)",
                    systemImage: "minus.circle",
                    isEnabled: !isLocked
                ) { vm.removeMicrophoneTrack(track.deviceID) })])
            }
            .popover(isPresented: $showsPicker, arrowEdge: .trailing) {
                BlitzSourcePickerPopover(model: MicrophoneTrackPickerModel.change(track: track, vm: vm)) { showsPicker = false }
            }
            .onChange(of: isLocked) { if isLocked { showsPicker = false } }
            meter
                .padding(.horizontal, 4)
                .padding(.vertical, 5)
                .frame(height: 24)
                .background(BlitzUI.insetWell, in: .rect(cornerRadius: InputFieldSlot.radius, style: .continuous))
                .padding(.trailing, 44)
        }
    }

    @ViewBuilder
    private var meter: some View {
        if let levels = vm.microphoneTrackLevels.levelsByDeviceID[track.deviceID], track.isConnected {
            BlitzLevelMeter(levels: levels, active: true)
        } else {
            Color.clear
        }
    }
}

@MainActor
private enum MicrophoneTrackPickerModel {
    static func add(vm: RecorderViewModel) -> BlitzSourcePickerModel {
        model(.init(title: "Add microphone", prompt: "Choose the next microphone", vm: vm,
                    choose: { vm.addMicrophoneTrack($0) }, actions: []))
    }

    static func change(track: MicrophoneTrackItem, vm: RecorderViewModel) -> BlitzSourcePickerModel {
        model(.init(
            title: track.name,
            prompt: "Choose the microphone for \(track.name)",
            vm: vm,
            choose: { vm.replaceMicrophoneTrack(.init(oldDeviceID: track.deviceID, newDeviceID: $0)) },
            actions: [
                BlitzSourcePickerItem(
                    id: "microphone-track:remove:\(track.deviceID)",
                    title: "Remove \(track.name)",
                    subtitle: nil,
                    systemImage: "minus.circle",
                    icon: nil,
                    thumbnail: nil,
                    isSelected: false
                ) { vm.removeMicrophoneTrack(track.deviceID) }
            ]
        ))
    }

    private struct Request {
        let title: String
        let prompt: String
        let vm: RecorderViewModel
        let choose: (String) -> Void
        let actions: [BlitzSourcePickerItem]
    }

    private static func model(_ request: Request) -> BlitzSourcePickerModel {
        BlitzSourcePickerModel(
            title: request.title,
            subtitle: "Microphone",
            systemImage: BlitzSymbols.microphone,
            icon: nil,
            sections: [BlitzSourcePickerSection(title: "Microphones", items: request.vm.microphoneTrackCandidates.map { option in
                BlitzSourcePickerItem(
                    id: "microphone:\(option.id)",
                    title: option.name,
                    subtitle: nil,
                    systemImage: BlitzSymbols.microphone,
                    icon: nil,
                    thumbnail: nil,
                    isSelected: false
                ) { request.choose(option.id) }
            })],
            actions: request.actions,
            layout: .list,
            enabled: request.vm.state == .idle,
            prompt: request.prompt,
            refresh: { await request.vm.refreshSources() }
        )
    }
}

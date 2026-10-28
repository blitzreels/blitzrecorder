import AppKit
import AVFoundation
import SwiftUI

@MainActor
struct CameraSourcePickerModel {
    let vm: RecorderViewModel
    let enabled: Bool

    private var selectedName: String {
        guard vm.isSourceConfigured(.camera) else { return "No camera" }
        if vm.isRemoteCameraSelected {
            return vm.selectedRemoteCameraName ?? "Remote iPhone"
        }
        if let selectedCameraID = vm.settings.selectedCameraID,
           let option = vm.localCameraOptions.first(where: { $0.id == selectedCameraID }) {
            return option.name
        }
        return "Default camera"
    }

    /// The main camera is in use: picking it again is a no-op, and ⌘-click can add the others as angles.
    private var isOn: Bool { vm.isSourceConfigured(.camera) }

    var model: BlitzSourcePickerModel {
        BlitzSourcePickerModel(
            title: selectedName,
            subtitle: vm.isRemoteCameraSelected ? "Wireless iPhone camera" : "Camera input",
            systemImage: vm.isRemoteCameraSelected ? "iphone.gen3" : BlitzSymbols.camera,
            icon: nil,
            sections: cameraSections,
            actions: actions,
            layout: .list,
            enabled: enabled && vm.state == .idle,
            prompt: "Choose camera",
            refresh: {
                vm.startRemoteCameraDiscovery()
                await vm.refreshSources()
            }
        )
    }


    private func isAngleCandidate(_ option: SourceOption) -> Bool {
        option.cameraKind != .deskView && option.id != vm.coordinator.mainLocalCameraDeviceID
    }

    private var actions: [BlitzSourcePickerItem] {
        var actions = [
            BlitzSourcePickerItem(
                id: "camera:manage",
                title: "Connect an iPhone…",
                subtitle: nil,
                systemImage: "iphone.radiowaves.left.and.right",
                icon: nil,
                thumbnail: nil,
                isSelected: false
            ) {
                vm.showSettings(.devices)
            }
        ]
        if isOn {
            actions.append(BlitzSourcePickerItem(
                id: "camera:none",
                title: "No camera",
                subtitle: "Record without a camera",
                systemImage: "video.slash",
                icon: nil,
                thumbnail: nil,
                isSelected: false
            ) {
                vm.removeSource(.camera)
            })
        }
        return actions
    }

    private var cameraSections: [BlitzSourcePickerSection] {
        let systemDefault = AVCaptureDevice.default(for: .video).map { CameraOptionName.plain($0.localizedName) }
        let defaultItem = BlitzSourcePickerItem(
            id: "camera:default",
            title: "Default camera",
            subtitle: systemDefault.map { "Follow macOS default · now \($0)" } ?? "Follow the macOS default",
            systemImage: "camera",
            icon: nil,
            thumbnail: nil,
            isSelected: isOn && vm.settings.selectedCameraID == nil
        ) {
            vm.setCamera(nil)
            vm.turnOnSource(.camera)
        }
        let local = vm.localCameraOptions.filter { $0.cameraKind?.isContinuity != true }
        let continuity = vm.localCameraOptions.filter { $0.cameraKind?.isContinuity == true }
        let remoteItems = vm.remoteCameraOptions.map { option in
            BlitzSourcePickerItem(
                id: "camera:\(option.id)",
                title: option.name,
                subtitle: "BlitzRecorder Camera · best quality",
                systemImage: "iphone.gen3",
                icon: nil,
                thumbnail: nil,
                isSelected: isOn && vm.settings.selectedCameraID == option.id
            ) {
                vm.setCamera(option.id)
                vm.turnOnSource(.camera)
            }
        }
        return [
            BlitzSourcePickerSection(title: "iPhone with BlitzRecorder Camera", items: remoteItems),
            BlitzSourcePickerSection(title: "Connected cameras", items: local.map(cameraItem)),
            BlitzSourcePickerSection(title: "Continuity & Desk View", items: continuity.map(cameraItem)),
            BlitzSourcePickerSection(title: "Automatic", items: [defaultItem])
        ]
    }

    private func cameraItem(_ option: SourceOption) -> BlitzSourcePickerItem {
        let kind = option.cameraKind ?? .external
        let angle = vm.cameraAngles.first { $0.deviceID == option.id }
        let isMain = isOn && vm.settings.selectedCameraID == option.id
        let subtitle: String = if let angle {
            "Recording as \(angle.name)"
        } else if isMain, !vm.cameraAngles.isEmpty {
            "\(vm.mainCameraTitle) · \(kind.subtitle)"
        } else {
            kind.subtitle
        }
        return BlitzSourcePickerItem(
            id: "camera:\(option.id)",
            title: CameraOptionName.plain(option.name),
            subtitle: subtitle,
            systemImage: kind.systemImage,
            icon: nil,
            thumbnail: nil,
            isSelected: isMain
        ) {
            if NSEvent.modifierFlags.contains(.command), isOn, isAngleCandidate(option) {
                if angle != nil {
                    vm.removeCameraAngle(option.id)
                } else {
                    vm.addCameraAngle(option.id)
                }
                return
            }
            vm.setCamera(option.id)
            vm.turnOnSource(.camera)
        }
    }
}

@MainActor
struct MicrophoneSourcePickerModel {
    let vm: RecorderViewModel
    let enabled: Bool

    private var isOn: Bool { vm.isSourceConfigured(.microphone) }

    var model: BlitzSourcePickerModel {
        BlitzSourcePickerModel(
            title: isOn ? vm.selectedMicrophoneDisplayName : "No microphone",
            subtitle: "Microphone input",
            systemImage: BlitzSymbols.microphone,
            icon: nil,
            sections: microphoneSections,
            actions: actions,
            layout: .list,
            enabled: enabled && vm.state != .starting && vm.state != .finishing,
            prompt: "Choose microphone"
        )
    }


    private var actions: [BlitzSourcePickerItem] {
        guard isOn, vm.state == .idle else { return [] }
        return [BlitzSourcePickerItem(
            id: "microphone:none",
            title: "No microphone",
            subtitle: "Record without your voice",
            systemImage: "mic.slash",
            icon: nil,
            thumbnail: nil,
            isSelected: false
        ) {
            vm.removeSource(.microphone)
        }]
    }

    /// Microphones that belong to a camera, such as an Osmo Pocket's, keyed by microphone ID.
    private var cameraNamesByMicrophoneID: [String: String] {
        var names: [String: String] = [:]
        for camera in vm.localCameraOptions {
            if let microphone = vm.pairedMicrophone(cameraDeviceID: camera.id) {
                names[microphone.id] = CameraOptionName.plain(camera.name)
            }
        }
        return names
    }

    private var microphoneSections: [BlitzSourcePickerSection] {
        let items = microphoneItems
        return [
            BlitzSourcePickerSection(title: "Microphones", items: Array(items.dropFirst())),
            BlitzSourcePickerSection(title: "Automatic", items: Array(items.prefix(1)))
        ]
    }

    /// The macOS default first, then every connected microphone, then a preferred one that is unplugged.
    private var microphoneItems: [BlitzSourcePickerItem] {
        let systemDefault = AVCaptureDevice.default(for: .audio)?.localizedName
        let defaultItem = BlitzSourcePickerItem(
            id: "microphone:default",
            title: "Default microphone",
            subtitle: systemDefault.map { "Follow macOS default · now \($0)" } ?? "Follow the macOS default",
            systemImage: BlitzSymbols.microphone,
            icon: nil,
            thumbnail: nil,
            isSelected: isOn && vm.settings.selectedMicrophoneID == nil
        ) {
            vm.setMicrophone(nil)
            vm.turnOnSource(.microphone)
        }
        let cameraNames = cameraNamesByMicrophoneID
        var items = [defaultItem] + vm.availableMicrophones.map { option in
            microphoneItem(option, cameraName: cameraNames[option.id])
        }
        if let missing = vm.missingPreferredMicrophone {
            items.append(BlitzSourcePickerItem(
                id: "microphone:missing",
                title: missing.preferredName,
                subtitle: "Not connected · used again when plugged in",
                systemImage: "mic.badge.xmark",
                icon: nil,
                thumbnail: nil,
                isSelected: false,
                isEnabled: false
            ) {})
        }
        return items
    }

    private func microphoneItem(_ option: SourceOption, cameraName: String?) -> BlitzSourcePickerItem {
        let track = vm.microphoneTracks.first { $0.deviceID == option.id }
        let isMain = isOn && vm.settings.selectedMicrophoneID == option.id
        let facts = [
            track.map { "Recording as \($0.name)" },
            isMain && !vm.microphoneTracks.isEmpty ? vm.mainMicrophoneTitle : nil,
            cameraName.map { "From \($0)" }
        ].compactMap { $0 }
        return BlitzSourcePickerItem(
            id: "microphone:\(option.id)",
            title: option.name,
            subtitle: facts.isEmpty ? nil : facts.joined(separator: " · "),
            systemImage: BlitzSymbols.microphone,
            icon: nil,
            thumbnail: nil,
            isSelected: isMain
        ) {
            if NSEvent.modifierFlags.contains(.command), isOn, vm.state == .idle,
               option.id != vm.coordinator.mainMicrophoneDeviceID {
                if track != nil {
                    vm.removeMicrophoneTrack(option.id)
                } else {
                    vm.addMicrophoneTrack(option.id)
                }
                return
            }
            if track != nil { vm.removeMicrophoneTrack(option.id) }
            vm.setMicrophone(option.id)
            vm.turnOnSource(.microphone)
        }
    }
}

@MainActor
struct ScreenCaptureSourcePickerModel {
    let vm: RecorderViewModel
    let enabled: Bool

    private var captureSourceLabel: String {
        vm.hasActiveScreenPickerSelection ? vm.selectedScreenSourceDisplayName : "Choose screen or window"
    }

    private var selectedScreenSourceIcon: NSImage? {
        selectedScreenSourceOption?.icon
            ?? vm.settings.screenSourceBinding.flatMap { ScreenSourceCatalog.appIcon(for: $0) }
    }

    private var selectedScreenSourceOption: ScreenSourceOption? {
        guard !vm.settings.usesPickedScreenContent,
              let binding = vm.settings.screenSourceBinding else {
            return nil
        }
        return vm.availableScreenSources.first {
            ScreenSourcePickerOrganization.isSelected(.init(
                selectedBinding: binding, candidate: $0.binding, usesPickedContent: false
            ))
        }
    }

    private var selectedScreenSourceSystemImage: String {
        if vm.settings.usesPickedScreenContent {
            return "rectangle.dashed"
        }

        switch vm.settings.screenSourceBinding?.kind {
        case .application:
            return "app"
        case .window:
            return "macwindow"
        case .display, nil:
            return "display"
        }
    }

    var model: BlitzSourcePickerModel {
        return BlitzSourcePickerModel(
            title: captureSourceLabel,
            subtitle: selectedScreenSourceKindLabel,
            systemImage: selectedScreenSourceSystemImage,
            icon: selectedScreenSourceIcon,
            sections: [
                screenSourceSection((kind: .display, title: "Displays", group: .all)),
                screenSourceSection((kind: .application, title: "Suggested apps", group: .suggested)),
                screenSourceSection((kind: .application, title: "Apps", group: .standard)),
                screenSourceSection((kind: .window, title: "Windows", group: .standard))
            ],
            actions: [],
            layout: .thumbnails,
            enabled: enabled && vm.canAdjustScreenCapture,
            hiddenSections: [
                screenSourceSection((kind: .application, title: "Private apps", group: .sensitive)),
                screenSourceSection((kind: .window, title: "Private app windows", group: .sensitive)),
                screenSourceSection((kind: .application, title: "Utility apps", group: .utility)),
                screenSourceSection((kind: .window, title: "Small & utility windows", group: .utility))
            ],
            prompt: "Choose screen or window",
            refresh: { await vm.refreshSources() }
        )
    }

    private func screenSourceSection(
        _ request: (
            kind: ScreenSourceBinding.Kind,
            title: String,
            group: ScreenSourcePickerGroup
        )
    ) -> BlitzSourcePickerSection {
        let options = vm.availableScreenSources.filter {
            $0.binding.kind == request.kind
                && (request.group == .all || $0.pickerPlacement.group == request.group)
        }
        return BlitzSourcePickerSection(
            title: request.title,
            items: options.map { option in
                BlitzSourcePickerItem(
                    id: option.binding.runtimeID,
                    title: option.title,
                    subtitle: option.subtitle,
                    systemImage: option.systemImage,
                    icon: option.icon,
                    thumbnail: nil,
                    isSelected: ScreenSourcePickerOrganization.isSelected(.init(
                        selectedBinding: vm.settings.screenSourceBinding,
                        candidate: option.binding,
                        usesPickedContent: vm.settings.usesPickedScreenContent
                    )),
                    visibility: ScreenSourcePickerOrganization.visibility(option),
                    screenKind: option.binding.kind,
                    loadThumbnail: { await vm.screenSourceThumbnail(option.binding) }
                ) {
                    vm.setScreenSource(option.binding)
                }
            }
        )
    }

    private var selectedScreenSourceKindLabel: String {
        if !vm.hasActiveScreenPickerSelection {
            return "Nothing selected"
        }
        if vm.settings.usesPickedScreenContent {
            return "Screen capture"
        }
        switch vm.settings.screenSourceBinding?.kind {
        case .application:
            return "App window capture"
        case .window:
            return "Window capture"
        case .display, nil:
            return "Display capture"
        }
    }
}

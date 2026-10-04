import AppKit
import SwiftUI

@MainActor
struct CameraSourcePickerModel {
    let vm: RecorderViewModel
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

    var model: BlitzSourcePickerModel {
        BlitzSourcePickerModel(
            title: selectedName,
            subtitle: vm.isRemoteCameraSelected ? "Wireless iPhone camera" : "Camera input",
            systemImage: vm.isRemoteCameraSelected ? "iphone.gen3" : BlitzSymbols.camera,
            icon: nil,
            sections: cameraSections,
            actions: [
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
            ],
            layout: .list,
            enabled: enabled && vm.state == .idle,
            prompt: "Choose camera",
            refresh: { await vm.refreshSources() }
        )
    }

    private var cameraSections: [BlitzSourcePickerSection] {
        let defaultItem = BlitzSourcePickerItem(
            id: "camera:default",
            title: "Default camera",
            subtitle: "Follow the macOS default",
            systemImage: "camera",
            icon: nil,
            thumbnail: nil,
            isSelected: vm.settings.selectedCameraID == nil,
            visibility: .init(id: "camera:default", hiddenReason: nil)
        ) {
            vm.setCamera(nil)
        }
        let local = vm.localCameraOptions.filter { $0.cameraKind?.hiddenReason == nil }
        let continuity = vm.localCameraOptions.filter { $0.cameraKind?.hiddenReason != nil }
        let remoteItems = vm.remoteCameraOptions.map { option in
            BlitzSourcePickerItem(
                id: "camera:\(option.id)",
                title: option.name,
                subtitle: "Wireless iPhone camera",
                systemImage: "iphone.gen3",
                icon: nil,
                thumbnail: nil,
                isSelected: vm.settings.selectedCameraID == option.id,
                visibility: .init(id: "camera:\(option.id)", hiddenReason: nil)
            ) {
                vm.setCamera(option.id)
            }
        }
        return [
            BlitzSourcePickerSection(title: "Connected cameras", items: local.map(cameraItem)),
            BlitzSourcePickerSection(title: "Wireless iPhones", items: remoteItems),
            BlitzSourcePickerSection(title: "Automatic", items: [defaultItem]),
            BlitzSourcePickerSection(title: "Continuity & Desk View", items: continuity.map(cameraItem))
        ]
    }

    private func cameraItem(_ option: SourceOption) -> BlitzSourcePickerItem {
        let kind = option.cameraKind ?? .external
        let title = option.name
            .replacingOccurrences(of: " (Continuity)", with: "")
            .replacingOccurrences(of: " (Desk View)", with: "")
        return BlitzSourcePickerItem(
            id: "camera:\(option.id)",
            title: title,
            subtitle: kind.subtitle,
            systemImage: kind.systemImage,
            icon: nil,
            thumbnail: nil,
            isSelected: vm.settings.selectedCameraID == option.id,
            visibility: .init(id: "camera:\(option.id)", hiddenReason: kind.hiddenReason)
        ) {
            vm.setCamera(option.id)
        }
    }
}

@MainActor
struct MicrophoneSourcePickerModel {
    let vm: RecorderViewModel
    let enabled: Bool

    var model: BlitzSourcePickerModel {
        BlitzSourcePickerModel(
            title: vm.selectedMicrophoneDisplayName,
            subtitle: "Microphone input",
            systemImage: BlitzSymbols.microphone,
            icon: nil,
            sections: [BlitzSourcePickerSection(title: "Microphones", items: microphoneItems)],
            actions: [],
            layout: .list,
            enabled: enabled && vm.state != .starting && vm.state != .finishing
        )
    }

    private var microphoneItems: [BlitzSourcePickerItem] {
        let defaultItem = BlitzSourcePickerItem(
            id: "microphone:default",
            title: "Default microphone",
            subtitle: "Follow the macOS default",
            systemImage: BlitzSymbols.microphone,
            icon: nil,
            thumbnail: nil,
            isSelected: vm.settings.selectedMicrophoneID == nil
        ) {
            vm.setMicrophone(nil)
        }
        return [defaultItem] + vm.availableMicrophones.map { option in
            BlitzSourcePickerItem(
                id: "microphone:\(option.id)",
                title: option.name,
                subtitle: nil,
                systemImage: BlitzSymbols.microphone,
                icon: nil,
                thumbnail: nil,
                isSelected: vm.settings.selectedMicrophoneID == option.id
            ) {
                vm.setMicrophone(option.id)
            }
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

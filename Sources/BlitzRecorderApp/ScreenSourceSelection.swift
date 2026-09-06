import Foundation
import ScreenCaptureKit

struct ScreenSourceSelectionSnapshot: Equatable {
    let usesPickedContent: Bool
    let binding: ScreenSourceBinding?
    let selectedDisplayID: String?
    let crop: CGRect?
    let pickedContentSelectionID: UUID?
}

@MainActor
final class ScreenSourceSelection {
    struct DisplayRequest {
        let id: String?
        let settings: RecordingSettings
    }

    struct BindingRequest {
        let binding: ScreenSourceBinding
        let settings: RecordingSettings
    }

    struct PickedContentRequest {
        let filter: SCContentFilter
        let persistentBinding: ScreenSourceBinding?
        let fallbackSourceKind: ScreenSourceBinding.Kind?
        let settings: RecordingSettings
    }

    struct RestoreRequest {
        let snapshot: ScreenSourceSelectionSnapshot
        let settings: RecordingSettings
    }

    struct PickedContentRestoreRequest {
        let snapshotUsesPickedContent: Bool
        let hasActiveFilter: Bool
        let activeSelectionID: UUID?
        let snapshotSelectionID: UUID?
    }

    struct RuntimeState {
        let pickedContentFilter: SCContentFilter?
        let pickedContentKind: ScreenSourceBinding.Kind?
        let pickedContentSelectionID: UUID?
    }

    private(set) var pickedContentFilter: SCContentFilter?
    private(set) var pickedContentKind: ScreenSourceBinding.Kind?
    private(set) var pickedContentSelectionID: UUID?

    var hasActivePickedContent: Bool {
        pickedContentFilter != nil
    }

    func selectDisplay(_ request: DisplayRequest) -> RecordingSettings {
        var settings = request.settings
        settings.selectedDisplayID = request.id
        settings.screenSourceBinding = .display(id: request.id)
        settings.usesPickedScreenContent = false
        settings.screenCrop = nil
        settings.screenSourceAspectRatio = nil
        pickedContentFilter = nil
        pickedContentKind = nil
        pickedContentSelectionID = nil
        return settings
    }

    func selectBinding(_ request: BindingRequest) -> RecordingSettings {
        var settings = request.settings
        settings.screenSourceBinding = request.binding
        if request.binding.kind == .display {
            settings.selectedDisplayID = request.binding.displayID
        }
        settings.usesPickedScreenContent = false
        settings.screenCrop = nil
        settings.screenSourceAspectRatio = nil
        pickedContentFilter = nil
        pickedContentKind = nil
        pickedContentSelectionID = nil
        return settings
    }

    func selectPickedContent(_ request: PickedContentRequest) -> RecordingSettings {
        var settings = request.settings
        settings.screenSourceBinding = request.persistentBinding
        if let binding = request.persistentBinding {
            if binding.kind == .display {
                settings.selectedDisplayID = binding.displayID
            }
        }
        settings.usesPickedScreenContent = true
        settings.screenCrop = nil
        settings.screenSourceAspectRatio = nil
        pickedContentFilter = request.filter
        pickedContentKind = request.persistentBinding?.kind ?? request.fallbackSourceKind
        pickedContentSelectionID = UUID()
        return settings
    }

    func snapshot(from settings: RecordingSettings) -> ScreenSourceSelectionSnapshot {
        ScreenSourceSelectionSnapshot(
            usesPickedContent: settings.usesPickedScreenContent,
            binding: settings.screenSourceBinding,
            selectedDisplayID: settings.selectedDisplayID,
            crop: settings.screenCrop,
            pickedContentSelectionID: settings.usesPickedScreenContent ? pickedContentSelectionID : nil
        )
    }

    func restore(_ request: RestoreRequest) -> RecordingSettings {
        var settings = request.settings
        settings.selectedDisplayID = request.snapshot.selectedDisplayID
        settings.screenSourceBinding = request.snapshot.binding
        settings.usesPickedScreenContent = Self.canRestorePickedContent(.init(
            snapshotUsesPickedContent: request.snapshot.usesPickedContent,
            hasActiveFilter: pickedContentFilter != nil,
            activeSelectionID: pickedContentSelectionID,
            snapshotSelectionID: request.snapshot.pickedContentSelectionID
        ))
        settings.screenCrop = request.snapshot.crop
        return settings
    }

    static func canRestorePickedContent(_ request: PickedContentRestoreRequest) -> Bool {
        request.snapshotUsesPickedContent
            && request.hasActiveFilter
            && request.activeSelectionID != nil
            && request.activeSelectionID == request.snapshotSelectionID
    }

    func activeFilter(for settings: RecordingSettings) -> SCContentFilter? {
        settings.usesPickedScreenContent ? pickedContentFilter : nil
    }

    func runtimeState() -> RuntimeState {
        RuntimeState(
            pickedContentFilter: pickedContentFilter,
            pickedContentKind: pickedContentKind,
            pickedContentSelectionID: pickedContentSelectionID
        )
    }

    func restoreRuntimeState(_ state: RuntimeState) {
        pickedContentFilter = state.pickedContentFilter
        pickedContentKind = state.pickedContentKind
        pickedContentSelectionID = state.pickedContentSelectionID
    }

    func activePickedContentKind(for settings: RecordingSettings) -> ScreenSourceBinding.Kind? {
        settings.usesPickedScreenContent ? pickedContentKind : nil
    }
}

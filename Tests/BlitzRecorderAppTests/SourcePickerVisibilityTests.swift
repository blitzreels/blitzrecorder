import AppKit
import XCTest
@testable import BlitzRecorderApp

final class SourcePickerVisibilityTests: XCTestCase {
    func testContinuityIsHiddenByDefaultAndRestorableAcrossRelaunch() {
        let camera = SourcePickerVisibility(id: "camera:phone", hiddenReason: CameraSourceKind.continuity.hiddenReason)
        var preferences = SourcePickerPreferences(encoded: "{}")
        XCTAssertTrue(preferences.isHidden(camera))
        preferences.update(.init(id: camera.id, isHidden: false))
        let restored = SourcePickerPreferences(encoded: preferences.encoded)
        XCTAssertFalse(restored.isHidden(camera))
    }

    func testHidingOneSourceDoesNotHideAnotherAndCanBeReversed() {
        let first = SourcePickerVisibility(id: "camera:first", hiddenReason: nil)
        let second = SourcePickerVisibility(id: "camera:second", hiddenReason: nil)
        var preferences = SourcePickerPreferences(encoded: "invalid")
        preferences.update(.init(id: first.id, isHidden: true))
        XCTAssertTrue(preferences.isHidden(first))
        XCTAssertFalse(preferences.isHidden(second))
        preferences.update(.init(id: first.id, isHidden: false))
        XCTAssertFalse(preferences.isHidden(first))
    }

    func testSelectedHiddenSourceStaysVisibleWithoutChangingSelection() {
        var selections = 0
        let active = BlitzSourcePickerItem(
            id: "selected",
            title: "Selected Continuity camera", subtitle: nil, systemImage: "iphone", icon: nil,
            thumbnail: nil, isSelected: true,
            visibility: .init(id: "selected", hiddenReason: "Continuity"),
            action: { selections += 1 }
        )
        let hidden = BlitzSourcePickerItem(
            id: "hidden",
            title: "Desk View", subtitle: nil, systemImage: "deskview", icon: nil,
            thumbnail: nil, isSelected: false,
            visibility: .init(id: "hidden", hiddenReason: "Desk View"), action: {}
        )
        let model = BlitzSourcePickerModel(
            title: active.title, subtitle: "Camera", systemImage: "camera", icon: nil,
            sections: [.init(title: "Cameras", items: [active, hidden])],
            actions: [], layout: .list, enabled: true
        )
        let preferences = SourcePickerPreferences(encoded: "{}")
        XCTAssertEqual(model.organizedSections(.init(preferences: preferences, includeHidden: false))
            .flatMap(\.items).map(\.title), [active.title])
        XCTAssertEqual(model.organizedSections(.init(preferences: preferences, includeHidden: true))
            .flatMap(\.items).map(\.title), [hidden.title])
        XCTAssertEqual(selections, 0)
    }

    func testTinyAndUtilityWindowsAreCollapsedButNormalSmallWindowsRemain() {
        XCTAssertTrue(ScreenSourcePickerOrganization.isUtilityWindow(.init(
            size: CGSize(width: 900, height: 24), layer: 0, isSystemWindow: false
        )))
        XCTAssertTrue(ScreenSourcePickerOrganization.isUtilityWindow(.init(
            size: CGSize(width: 99, height: 800), layer: 0, isSystemWindow: false
        )))
        XCTAssertTrue(ScreenSourcePickerOrganization.isUtilityWindow(.init(
            size: CGSize(width: 900, height: 800), layer: 25, isSystemWindow: false
        )))
        XCTAssertTrue(ScreenSourcePickerOrganization.isUtilityWindow(.init(
            size: CGSize(width: 900, height: 800), layer: 0, isSystemWindow: true
        )))
        XCTAssertFalse(ScreenSourcePickerOrganization.isUtilityWindow(.init(
            size: CGSize(width: 180, height: 100), layer: 0, isSystemWindow: false
        )))
    }

    func testWindowVisibilitySurvivesRuntimeWindowIDChanges() {
        var binding = ScreenSourceBinding(
            kind: .window, displayID: nil, bundleIdentifier: "example.app", applicationName: "Example",
            processID: 100, windowID: 1, windowTitle: "Utility panel"
        )
        var option = ScreenSourceOption(
            binding: binding, title: "Utility panel", subtitle: "Example", systemImage: "macwindow", icon: nil,
            pickerPlacement: .utility
        )
        let first = ScreenSourcePickerOrganization.visibility(option)
        var preferences = SourcePickerPreferences(encoded: "{}")
        preferences.update(.init(id: first.id, isHidden: false))
        binding.windowID = 999
        binding.processID = 200
        option = ScreenSourceOption(
            binding: binding, title: "Utility panel", subtitle: "Example", systemImage: "macwindow", icon: nil,
            pickerPlacement: .utility
        )
        let reopened = ScreenSourcePickerOrganization.visibility(option)
        XCTAssertEqual(first.id, reopened.id)
        XCTAssertFalse(preferences.isHidden(reopened))
    }

    func testActiveWindowStaysSelectedWhenItsTitleChanges() {
        let selected = ScreenSourceBinding(
            kind: .window, displayID: nil, bundleIdentifier: "example.browser", applicationName: "Browser",
            processID: 100, windowID: 1, windowTitle: "Inbox (1)"
        )
        var refreshed = selected
        refreshed.windowTitle = "Inbox (2)"
        XCTAssertTrue(ScreenSourcePickerOrganization.isSelected(.init(
            selectedBinding: selected, candidate: refreshed, usesPickedContent: false
        )))
        refreshed.windowID = 2
        XCTAssertFalse(ScreenSourcePickerOrganization.isSelected(.init(
            selectedBinding: selected, candidate: refreshed, usesPickedContent: false
        )))
        XCTAssertFalse(ScreenSourcePickerOrganization.isSelected(.init(
            selectedBinding: selected, candidate: selected, usesPickedContent: true
        )))
    }

    @MainActor
    func testSoftwareCursorIsClassifiedAsAUtility() {
        XCTAssertTrue(RecorderCoordinator.isIgnoredScreenWindow(
            bundleIdentifier: "example.cursor", applicationName: "Cursor", title: "Software Cursor"
        ))
        XCTAssertFalse(RecorderCoordinator.isIgnoredScreenWindow(
            bundleIdentifier: "example.editor", applicationName: "Editor", title: "Project notes"
        ))
    }

    @MainActor
    func testPreviewPreservesPortraitAndLandscapeShapeWithoutUpscaling() {
        XCTAssertEqual(ScreenSourceThumbnailProvider.dimensions(CGSize(width: 1920, height: 1080)),
                       CGSize(width: 480, height: 270))
        XCTAssertEqual(ScreenSourceThumbnailProvider.dimensions(CGSize(width: 1080, height: 1920)),
                       CGSize(width: 168, height: 300))
        XCTAssertEqual(ScreenSourceThumbnailProvider.dimensions(CGSize(width: 80, height: 24)),
                       CGSize(width: 80, height: 24))
    }
}

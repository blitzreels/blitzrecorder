import AppKit
import XCTest
@testable import BlitzRecorderApp

final class BlitzMenuTests: XCTestCase {
    func testNavigationSkipsDisabledOptionsAndSectionChrome() {
        let entries: [BlitzMenuEntry] = [
            .section("Quality"),
            .item(BlitzMenuItem(title: "Normal", systemImage: nil, isSelected: true, action: {})),
            .divider,
            .item(BlitzMenuItem(title: "Unavailable", systemImage: nil, isEnabled: false, action: {})),
            .item(BlitzMenuItem(title: "High", systemImage: nil, isSelected: false, action: {}))
        ]

        XCTAssertEqual(BlitzMenuNavigation.initialIndex(entries), 1)
        XCTAssertEqual(BlitzMenuNavigation.movedIndex(.init(entries: entries, currentIndex: 1, offset: 1)), 4)
        XCTAssertEqual(BlitzMenuNavigation.movedIndex(.init(entries: entries, currentIndex: 4, offset: -1)), 1)
        XCTAssertEqual(BlitzMenuNavigation.movedIndex(.init(entries: entries, currentIndex: 4, offset: 1)), 4)
    }

    func testDisabledSelectionDoesNotReceiveKeyboardHighlight() {
        let entries: [BlitzMenuEntry] = [
            .item(BlitzMenuItem(title: "Unavailable", systemImage: nil, isSelected: true, isEnabled: false, action: {})),
            .item(BlitzMenuItem(title: "Available", systemImage: nil, action: {}))
        ]

        XCTAssertEqual(BlitzMenuNavigation.initialIndex(entries), 1)
        XCTAssertEqual(BlitzMenuNavigation.movedIndex(.init(entries: entries, currentIndex: 0, offset: 1)), 1)
    }

    func testMenuWithNoEnabledItemsHasNoSelection() {
        let entries: [BlitzMenuEntry] = [
            .section("Devices"),
            .item(BlitzMenuItem(title: "Offline", systemImage: nil, isEnabled: false, action: {}))
        ]

        XCTAssertNil(BlitzMenuNavigation.initialIndex(entries))
        XCTAssertNil(BlitzMenuNavigation.movedIndex(.init(entries: entries, currentIndex: 1, offset: 1)))
    }

    func testDisabledActionNeitherRunsNorDismissesMenu() {
        var events: [String] = []
        let item = BlitzMenuItem(title: "Unavailable", systemImage: nil, isEnabled: false) {
            events.append("action")
        }

        item.perform { events.append("dismiss") }

        XCTAssertTrue(events.isEmpty)
    }

    func testMenuClosesBeforeOpeningAnotherSurface() {
        var events: [String] = []
        let item = BlitzMenuItem(title: "Choose folder…", systemImage: "folder") {
            events.append("open panel")
        }

        item.perform { events.append("dismiss") }

        XCTAssertEqual(events, ["dismiss", "open panel"])
    }

    func testSourceChoicesAndCommandsKeepDifferentSemantics() {
        let source = BlitzSourcePickerItem(
            id: "source",
            title: "Microphone", subtitle: nil, systemImage: "mic", icon: nil,
            thumbnail: nil, isSelected: true, action: {}
        )
        let action = BlitzSourcePickerItem(
            id: "manage",
            title: "Manage devices…", subtitle: nil, systemImage: "gearshape", icon: nil,
            thumbnail: nil, isSelected: false, action: {}
        )
        let sections = [BlitzSourcePickerSection(title: "Inputs", items: [source])]
        let model = BlitzSourcePickerModel(
            title: "Microphone", subtitle: "Input", systemImage: "mic", icon: nil,
            sections: sections, actions: [action], layout: .list, enabled: true
        )
        let entries = model.menuEntries(sections)

        guard entries.count == 4, case .item(let choice) = entries[1],
              case .divider = entries[2], case .item(let command) = entries[3] else {
            return XCTFail("Choices and commands must be separated in the shared menu.")
        }
        XCTAssertEqual(choice.selection, true)
        XCTAssertNil(command.selection)
    }

    func testKeyboardHandlerLeavesApplicationShortcutsAlone() {
        XCTAssertNotNil(BlitzMenuKeyboardCommand.resolve(.init(keyCode: 125, modifiers: [])))
        XCTAssertNotNil(BlitzMenuKeyboardCommand.resolve(.init(keyCode: 36, modifiers: [])))
        XCTAssertNil(BlitzMenuKeyboardCommand.resolve(.init(keyCode: 125, modifiers: [.command])))
        XCTAssertNil(BlitzMenuKeyboardCommand.resolve(.init(keyCode: 36, modifiers: [.option])))
    }
}

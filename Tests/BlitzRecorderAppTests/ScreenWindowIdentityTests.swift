import XCTest
@testable import BlitzRecorderApp

final class ScreenWindowIdentityTests: XCTestCase {
    private var binding: ScreenSourceBinding {
        .init(kind: .window, displayID: "1", bundleIdentifier: "example.editor", applicationName: "Editor",
              processID: 100, windowID: 10, windowTitle: "Untitled")
    }

    func testSameTitleDoesNotSubstituteAnotherWindow() throws {
        let identity = try XCTUnwrap(ScreenWindowIdentity(binding))
        var replacement = binding
        replacement.windowID = 11
        XCTAssertFalse(identity.matches(try XCTUnwrap(ScreenWindowIdentity(replacement))))
        XCTAssertNotEqual(binding.runtimeID, replacement.runtimeID)
    }

    func testReusedWindowIDMustMatchBothOwnerAndProcess() throws {
        let identity = try XCTUnwrap(ScreenWindowIdentity(binding))
        var replacement = binding
        replacement.processID = 200
        XCTAssertFalse(identity.matches(try XCTUnwrap(ScreenWindowIdentity(replacement))))
        XCTAssertFalse(ScreenSourcePickerOrganization.isSelected(.init(
            selectedBinding: binding, candidate: replacement, usesPickedContent: false
        )))
        XCTAssertNotEqual(binding.runtimeID, replacement.runtimeID)
        replacement = binding
        replacement.bundleIdentifier = "example.private"
        XCTAssertFalse(identity.matches(try XCTUnwrap(ScreenWindowIdentity(replacement))))
        XCTAssertNotEqual(binding.runtimeID, replacement.runtimeID)
    }

    func testRenamingOrMovingWindowKeepsRuntimeIdentity() throws {
        let identity = try XCTUnwrap(ScreenWindowIdentity(binding))
        var renamed = binding
        renamed.windowTitle = "Saved document"
        renamed.displayID = "2"
        XCTAssertEqual(binding.runtimeID, renamed.runtimeID)
        XCTAssertTrue(identity.matches(try XCTUnwrap(ScreenWindowIdentity(renamed))))
    }

    func testMissingWindowIDRequiresReselection() {
        var legacy = binding
        legacy.windowID = nil
        XCTAssertNil(ScreenWindowIdentity(legacy))
        XCTAssertNil(ScreenWindowIdentity(.display(id: "1")))
    }

    func testLegacyBindingStillChecksKnownOwner() throws {
        var legacy = binding
        legacy.processID = nil
        let identity = try XCTUnwrap(ScreenWindowIdentity(legacy))
        XCTAssertTrue(identity.matches(try XCTUnwrap(ScreenWindowIdentity(binding))))
        var replacement = binding
        replacement.bundleIdentifier = "example.private"
        XCTAssertFalse(identity.matches(try XCTUnwrap(ScreenWindowIdentity(replacement))))
    }
}

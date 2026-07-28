@testable import BlitzRecorderApp
import XCTest

final class ScreenSourcePickerOrganizationTests: XCTestCase {
    private struct OptionRequest {
        let name: String
        let bundleIdentifier: String
    }

    func testPreferredAppsAreSuggestedInProductOrder() {
        let options = [
            option(OptionRequest(name: "Codex", bundleIdentifier: "com.openai.codex")),
            option(OptionRequest(name: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode")),
            option(OptionRequest(name: "Google Chrome", bundleIdentifier: "com.google.Chrome")),
            option(OptionRequest(name: "Calendar", bundleIdentifier: "com.apple.iCal"))
        ].map { option in
            var option = option
            option.pickerPlacement = ScreenSourcePickerOrganization.placement(
                ScreenSourcePickerPlacementRequest(
                    binding: option.binding,
                    recentBundleIdentifiers: []
                )
            )
            return option
        }

        XCTAssertEqual(
            ScreenSourcePickerOrganization.sorted(options).map(\.title),
            ["Google Chrome", "Visual Studio Code", "Codex", "Calendar"]
        )
    }

    func testRecentAppMovesAheadOfBuiltInSuggestions() {
        let safari = option(OptionRequest(name: "Safari", bundleIdentifier: "com.apple.Safari"))
        let placement = ScreenSourcePickerOrganization.placement(
            ScreenSourcePickerPlacementRequest(
                binding: safari.binding,
                recentBundleIdentifiers: ["com.apple.Safari"]
            )
        )

        XCTAssertEqual(placement, .suggested(rank: 0))
    }

    func testBitwardenAndHandyArePrivate() {
        let bitwarden = option(OptionRequest(name: "Bitwarden", bundleIdentifier: "com.bitwarden.desktop"))
        let handy = option(OptionRequest(name: "Handy", bundleIdentifier: "com.pais.handy"))

        XCTAssertEqual(placement(for: bitwarden), .sensitive)
        XCTAssertEqual(placement(for: handy), .sensitive)
    }

    func testPrivateAppStaysHiddenWhenItIsRecent() {
        let bitwarden = option(OptionRequest(name: "Bitwarden", bundleIdentifier: "com.bitwarden.desktop"))
        let placement = ScreenSourcePickerOrganization.placement(
            ScreenSourcePickerPlacementRequest(
                binding: bitwarden.binding,
                recentBundleIdentifiers: ["com.bitwarden.desktop"]
            )
        )

        XCTAssertEqual(placement, .sensitive)
    }

    func testRecentsAreMostRecentFirstDeduplicatedAndBounded() {
        var recents = ["one", "two", "three", "four", "five"]
        recents = ScreenSourcePickerOrganization.updatedRecentBundleIdentifiers(
            ScreenSourcePickerRecentUpdateRequest(
                bundleIdentifier: "three",
                existingBundleIdentifiers: recents
            )
        )
        recents = ScreenSourcePickerOrganization.updatedRecentBundleIdentifiers(
            ScreenSourcePickerRecentUpdateRequest(
                bundleIdentifier: "six",
                existingBundleIdentifiers: recents
            )
        )

        XCTAssertEqual(recents, ["six", "three", "one", "two", "four"])
    }

    private func placement(for option: ScreenSourceOption) -> ScreenSourcePickerPlacement {
        ScreenSourcePickerOrganization.placement(
            ScreenSourcePickerPlacementRequest(
                binding: option.binding,
                recentBundleIdentifiers: []
            )
        )
    }

    private func option(_ request: OptionRequest) -> ScreenSourceOption {
        ScreenSourceOption(
            binding: ScreenSourceBinding(
                kind: .application,
                displayID: nil,
                bundleIdentifier: request.bundleIdentifier,
                applicationName: request.name,
                processID: nil,
                windowID: nil,
                windowTitle: nil
            ),
            title: request.name,
            subtitle: "Main window",
            systemImage: "macwindow.on.rectangle",
            icon: nil
        )
    }
}

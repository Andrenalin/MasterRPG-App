// @copyright André Trettin

import AppIntentsTesting
import XCTest

/// `NavigateIntent` and its `NavigationOption` `AppEnum`.
@available(iOS 27, macOS 27, *)
final class NavigateIntentTests: AppIntentsUITestCase {
    /// Every `NavigationOption` case and the accessibility token of its module. Modules with a
    /// list show `module.list.<token>`; the others (game, search) are checked by their selected tab.
    private static let options: [(rawValue: String, token: String?, hasList: Bool)] = [
        ("adventure", "ADVENTURES", true),
        ("audio", "AUDIOS", true),
        ("character", "VALUES", true),
        ("dice", "DICE", true),
        ("game", "GAME", false),
        ("generator", nil, false),
        ("map", "MAPS", true),
        ("pdf", "PDFS", true),
        ("photo", "PHOTOS", true),
        ("rule", nil, false),
        ("search", "SEARCH", false),
        ("space", "SPACES", true),
        ("table", "TABLES", true),
        ("weather", "WEATHERS", true)
    ]

    func testNavigationOptionExposesEveryCase() {
        let option = definitions.enums["NavigationOption"]
        XCTAssertEqual(option.typeIdentifier, "NavigationOption")
        for (rawValue, _, _) in Self.options {
            XCTAssertEqual(option.makeCase(rawValue).rawValue, rawValue)
        }
    }

    func testNavigateRunsForEveryOption() async {
        for (rawValue, _, _) in Self.options {
            do {
                try await definitions.intents["NavigateIntent"].makeIntent(navigationOption: rawValue).run()
            } catch {
                XCTFail("\(rawValue): \(error)")
            }
        }
    }

    func testNavigateShowsTheRequestedModule() async throws {
        for (rawValue, token, hasList) in Self.options {
            guard let token else { continue }
            try await definitions.intents["NavigateIntent"].makeIntent(navigationOption: rawValue).run()

            if hasList {
                let list = app.descendants(matching: .any)
                    .matching(identifier: "module.list.\(token)")
                    .firstMatch
                XCTAssertTrue(list.waitForExistence(timeout: 15), "Navigating to \(rawValue) did not show \(token).")
            } else {
                await eventually("Navigating to \(rawValue) did not select the \(token) tab.") {
                    let tab = app.descendants(matching: .any)
                        .matching(identifier: "module.tab.\(token)")
                        .firstMatch
                    // Reading `isSelected` of a missing element fails the test instead of retrying.
                    return tab.exists && tab.isSelected
                }
            }
        }
    }

    func testNavigateAcceptsAnEnumCase() async throws {
        let value = definitions.enums["NavigationOption"].makeCase("map")
        try await definitions.intents["NavigateIntent"].makeIntent(navigationOption: value).run()
    }
}

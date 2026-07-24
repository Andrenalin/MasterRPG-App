// @copyright André Trettin

import XCTest

final class GameSettingsAndSearchUITests: MasterRPGUITestCase {
    @MainActor
    func testGameStatisticsDashboardSettingsToggleAndDismiss() {
        let app = launchPreparedApp()
        openModule(token: "GAME", title: "Game", app: app)

        let statistics = app.buttons
            .containing(.staticText, identifier: "Game Statistics")
            .firstMatch
        XCTAssertTrue(statistics.waitForExistence(timeout: 15))
        statistics.tap()

        XCTAssertTrue(app.staticTexts["Game Statistics"].firstMatch.waitForExistence(timeout: 15))

        let customize = app.buttons["Customize"].firstMatch
        XCTAssertTrue(customize.waitForExistence(timeout: 10))
        customize.tap()
        XCTAssertTrue(app.staticTexts["Collect Game Statistics"].firstMatch.waitForExistence(timeout: 10))

        let dashboard = app.buttons["Dashboard"].firstMatch
        XCTAssertTrue(dashboard.waitForExistence(timeout: 10))
        dashboard.tap()
        XCTAssertTrue(app.staticTexts["Your Adventures, Visualized"].firstMatch.waitForExistence(timeout: 10))

        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        done.tap()
        XCTAssertTrue(statistics.waitForExistence(timeout: 10))
    }

    @MainActor
    func testThemeChooserStaysPresentedAndReopens() {
        let app = launchPreparedApp()
        openModule(token: "SETTINGS", title: "Settings", app: app)

        let chooseTheme = app.descendants(matching: .any)
            .matching(identifier: "settings.theme.choose")
            .firstMatch
        XCTAssertTrue(chooseTheme.waitForExistence(timeout: 15))
        chooseTheme.tap()

        XCTAssertTrue(app.staticTexts["Choose Theme"].firstMatch.waitForExistence(timeout: 10))
        let midnight = app.buttons["Midnight"].firstMatch
        XCTAssertTrue(midnight.waitForExistence(timeout: 10))
        midnight.tap()
        XCTAssertTrue(app.staticTexts["Choose Theme"].firstMatch.exists)

        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(chooseTheme.waitForExistence(timeout: 10))

        chooseTheme.tap()
        XCTAssertTrue(app.staticTexts["Choose Theme"].firstMatch.waitForExistence(timeout: 10))
    }

    @MainActor
    func testGlobalSearchRouteShowsInput() {
        let app = launchPreparedApp()
        openModule(token: "SEARCH", title: "Search", app: app)

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        XCTAssertTrue(search.isHittable)
    }
}

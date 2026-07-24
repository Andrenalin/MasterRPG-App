// @copyright André Trettin

import XCTest

class MasterRPGUITestCase: XCTestCase {
    @MainActor
    func launchPreparedApp() -> XCUIApplication {
        continueAfterFailure = false

        let app = XCUIApplication()
        app.launchArguments = [
            "-allowCloudKitSync", "0",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()

        let initialize = app.buttons["Initialize"]
        if initialize.waitForExistence(timeout: 3) {
            initialize.tap()
            let installed = app.buttons["OK"]
            XCTAssertTrue(installed.waitForExistence(timeout: 20))
            installed.tap()
        }

        addTeardownBlock { [weak self, weak app] in
            guard let self, let app, self.testRun?.failureCount ?? 0 > 0 else { return }
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.lifetime = .keepAlways
            self.add(attachment)
        }
        return app
    }

    @MainActor
    func openModule(
        token: String,
        title: String,
        app: XCUIApplication,
        timeout: TimeInterval = 15
    ) {
        let identifier = "module.tab.\(token)"
        let identifiedTab = app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch

        if identifiedTab.waitForExistence(timeout: 2) {
            identifiedTab.tap()
            return
        }

        let sidebarToggle = app.buttons["ToggleSideBar"].firstMatch
        if sidebarToggle.exists && sidebarToggle.isHittable {
            sidebarToggle.tap()
            if identifiedTab.waitForExistence(timeout: 5) {
                identifiedTab.tap()
                return
            }
        }

        if token == "SETTINGS" {
            let settingsTab = app.buttons["Tab.Util"].firstMatch
            XCTAssertTrue(
                settingsTab.waitForExistence(timeout: timeout),
                "The Settings module tab is missing."
            )
            settingsTab.tap()
            return
        }

        let titledButton = app.buttons[title].firstMatch
        XCTAssertTrue(
            titledButton.waitForExistence(timeout: timeout),
            "The \(title) module tab is missing."
        )
        titledButton.tap()
    }

    @MainActor
    func assertModuleNavigationAndCreateAction(
        token: String,
        title: String,
        app: XCUIApplication,
        persistsItem: Bool = false
    ) {
        openModule(token: token, title: title, app: app)

        let listIdentifier = "module.list.\(token)"
        let list = app.descendants(matching: .any)
            .matching(identifier: listIdentifier)
            .firstMatch
        XCTAssertTrue(
            list.waitForExistence(timeout: 15),
            "The \(title) module did not display its list."
        )

        let addItem = app.buttons["Add Item"].firstMatch
        XCTAssertTrue(
            addItem.waitForExistence(timeout: 10),
            "The \(title) module has no add-item action."
        )
        addItem.tap()

        let nameField = app.textFields.firstMatch
        XCTAssertTrue(
            nameField.waitForExistence(timeout: 15),
            "Creating a \(title) item did not open the header editor."
        )

        let clearName = app.buttons["Clear name"].firstMatch
        if clearName.exists && clearName.isHittable {
            clearName.tap()
        }

        let name = "UI \(title) \(UUID().uuidString.prefix(6))"
        nameField.tap()
        nameField.typeText(name)

        let save = app.buttons["Save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)

        if persistsItem {
            save.tap()
            XCTAssertTrue(
                app.staticTexts[name].firstMatch.waitForExistence(timeout: 15),
                "The saved \(title) item did not appear after the editor action."
            )
        } else {
            let cancel = app.buttons["Cancel"].firstMatch
            XCTAssertTrue(cancel.waitForExistence(timeout: 5))
            cancel.tap()
            XCTAssertTrue(
                cancel.waitForNonExistence(timeout: 10),
                "Cancelling the \(title) editor did not dismiss it."
            )
        }
    }
}

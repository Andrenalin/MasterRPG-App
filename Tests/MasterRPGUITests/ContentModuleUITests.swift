// @copyright André Trettin

import XCTest

final class ContentModuleUITests: MasterRPGUITestCase {
    @MainActor
    func testAdventureAskAIAccessoryAcceptsKeyboardInput() {
        let app = launchPreparedApp()
        openModule(token: "ADVENTURES", title: "Adventure", app: app)

        let adventure = app.staticTexts["00 Adventure"].firstMatch
        XCTAssertTrue(adventure.waitForExistence(timeout: 15))
        adventure.tap()

        let askAI = app.buttons["Ask AI"].firstMatch
        XCTAssertTrue(askAI.waitForExistence(timeout: 15))
        XCTAssertTrue(askAI.isHittable)
        askAI.tap()

        let prompt = app.textFields["Ask AI"].firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 10))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))

        let request = "Create a mysterious encounter"
        prompt.typeText(request)
        XCTAssertEqual(prompt.value as? String, request)
    }

    @MainActor
    func testAdventureNavigationAndCreateAction() {
        let app = launchPreparedApp()
        assertModuleNavigationAndCreateAction(
            token: "ADVENTURES",
            title: "Adventure",
            app: app,
            persistsItem: true
        )
    }

    @MainActor
    func testCharacterNavigationAndCreateAction() {
        let app = launchPreparedApp()
        assertModuleNavigationAndCreateAction(
            token: "VALUES",
            title: "Character",
            app: app
        )
    }

    @MainActor
    func testMapNavigationAndCreateAction() {
        let app = launchPreparedApp()
        assertModuleNavigationAndCreateAction(
            token: "MAPS",
            title: "Map",
            app: app
        )
    }

    @MainActor
    func testWeatherNavigationAndCreateAction() {
        let app = launchPreparedApp()
        assertModuleNavigationAndCreateAction(
            token: "WEATHERS",
            title: "Weather",
            app: app
        )
    }

    @MainActor
    func testPDFNavigationAndCreateAction() {
        let app = launchPreparedApp()
        assertModuleNavigationAndCreateAction(
            token: "PDFS",
            title: "Pdf",
            app: app
        )
    }

    @MainActor
    func testTableNavigationAndCreateAction() {
        let app = launchPreparedApp()
        assertModuleNavigationAndCreateAction(
            token: "TABLES",
            title: "Table",
            app: app
        )
    }

    @MainActor
    func testAudioNavigationAndCreateAction() {
        let app = launchPreparedApp()
        assertModuleNavigationAndCreateAction(
            token: "AUDIOS",
            title: "Audio",
            app: app
        )
    }

    @MainActor
    func testDiceNavigationAndCreateAction() {
        let app = launchPreparedApp()
        assertModuleNavigationAndCreateAction(
            token: "DICE",
            title: "Dice",
            app: app
        )
    }

    @MainActor
    func testPhotoNavigationAndCreateAction() {
        let app = launchPreparedApp()
        assertModuleNavigationAndCreateAction(
            token: "PHOTOS",
            title: "Photo",
            app: app
        )
    }

    @MainActor
    func testSpaceNavigationAndCreateAction() {
        let app = launchPreparedApp()
        assertModuleNavigationAndCreateAction(
            token: "SPACES",
            title: "Space",
            app: app
        )
    }
}

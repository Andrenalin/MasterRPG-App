// @copyright André Trettin

import XCTest

final class ContentModuleUITests: MasterRPGUITestCase {
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

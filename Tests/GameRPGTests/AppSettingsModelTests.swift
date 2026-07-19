// @copyright André Trettin

import Foundation
import Testing
@testable import CoreRPG

@MainActor
@Suite("App settings", .serialized)
struct AppSettingsModelTests {
    @Test("Game dice visibility uses visible defaults")
    func defaultGameDiceVisibility() throws {
        let suiteName = "AppSettingsModelTests.default.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = AppSettingsModel(defaults: defaults)

        #expect(model.showGameDice)
        #expect(model.showGamePlayerDice)
    }

    @Test("Game dice visibility is restored by a new settings model")
    func restoreGameDiceVisibility() throws {
        let suiteName = "AppSettingsModelTests.restore.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstModel = AppSettingsModel(defaults: defaults)
        firstModel.showGameDice = false
        firstModel.showGamePlayerDice = false

        let restoredModel = AppSettingsModel(defaults: defaults)

        #expect(restoredModel.showGameDice == false)
        #expect(restoredModel.showGamePlayerDice == false)
    }
}

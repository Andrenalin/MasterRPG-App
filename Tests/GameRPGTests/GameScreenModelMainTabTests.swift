// @copyright André Trettin

#if canImport(Testing)
@testable import CoreRPG
import Foundation
import Testing

@testable import GameRPG

@MainActor
@Suite("Game screen main tab menu", .serialized)
struct GameScreenModelMainTabTests {
    private func makeSettings() throws -> (AppSettingsModel, cleanup: () -> Void) {
        let suiteName = "GameScreenModelMainTabTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return (AppSettingsModel(defaults: defaults), { defaults.removePersistentDomain(forName: suiteName) })
    }

    @Test("Toggle shows the master's game tab and persists the choice")
    func toggleMaster() throws {
        let (settings, cleanup) = try makeSettings()
        defer { cleanup() }
        let model = GameScreenModel()

        model.applyMainTabToggle(isShown: true, isMaster: true, settings: settings, animated: false)
        #expect(model.showMainTab == .game)
        #expect(settings.autoShowMasterMainTab)

        model.applyMainTabToggle(isShown: false, isMaster: true, settings: settings, animated: false)
        #expect(model.showMainTab == .none)
        #expect(!settings.autoShowMasterMainTab)
    }

    @Test("Toggle shows the player's character tab and leaves master settings alone")
    func togglePlayer() throws {
        let (settings, cleanup) = try makeSettings()
        defer { cleanup() }
        let model = GameScreenModel()
        let masterBefore = settings.autoShowMasterMainTab

        model.applyMainTabToggle(isShown: true, isMaster: false, settings: settings, animated: false)

        #expect(model.showMainTab == .value)
        #expect(settings.autoShowPlayerMainTab)
        #expect(settings.autoShowMasterMainTab == masterBefore)
    }
}
#endif

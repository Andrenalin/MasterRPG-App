// @copyright André Trettin

import Foundation
import Testing

@testable import GameRPG

/// CODE_AUDIT_Since_3.0.1 §5.7: only the player setup screen loaded the saved character, so
/// Join Game by Siri failed in a run where that screen had not appeared.
@MainActor
@Suite("Restoring the selected character")
struct RestoreSelectedCharacterTests {
    private func defaults(_ playerId: String?) throws -> UserDefaults {
        let suite = "RestoreSelectedCharacterTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        if let playerId {
            defaults.set(playerId, forKey: GameStorageKeys.lastPlayerUUID)
        }
        return defaults
    }

    @Test("The saved character is loaded when none is selected")
    func loadsSavedCharacter() throws {
        let root = GameRoot.previewFixture(game: .player)
        root.gameModel.selectedCharacter = nil
        let playerId = UUID()

        root.restoreSelectedCharacter(defaults: try defaults(playerId.uuidString))

        #expect(root.gameModel.selectedCharacter == playerId)
    }

    @Test("A character chosen in this run is kept")
    func keepsChosenCharacter() throws {
        let root = GameRoot.previewFixture(game: .player)
        let chosen = UUID()
        root.gameModel.selectedCharacter = chosen

        root.restoreSelectedCharacter(defaults: try defaults(UUID().uuidString))

        #expect(root.gameModel.selectedCharacter == chosen)
    }

    @Test("Without a saved character nothing is selected")
    func nothingSaved() throws {
        let root = GameRoot.previewFixture(game: .player)
        root.gameModel.selectedCharacter = nil

        root.restoreSelectedCharacter(defaults: try defaults(nil))

        #expect(root.gameModel.selectedCharacter == nil)
    }
}

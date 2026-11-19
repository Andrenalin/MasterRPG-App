// @copyright André Trettin

#if canImport(Testing)
#if !os(tvOS)
import AppIntents
import CoreRPG
import Foundation
import Testing

@testable import GameRPG

/// CODE_AUDIT_TestGaps §5.9: what the game intents (Siri, Shortcuts, Control Center) answer when
/// the situation does not allow the action: no battle, no game, or a player's device. These run
/// outside the game screens, so a wrong answer is visible only in Siri.
@Suite("Game intent guards", .serialized)
@MainActor
struct GameIntentGuardTests {
    private func makeRoot(master: Bool, started: Bool = true) async throws -> GameRoot {
        let root = try await MockRoot.createGameRoot()
        let id = UUID()
        root.gameModel.gameConfig = GameConfigModel(
            id: master ? id : UUID(),
            state: started ? .started : .stopped,
            master: MasterGameModel(id: id, type: .master, name: "Master")
        )
        return root
    }

    /// The localization key of a dialog. Its reflection also holds object addresses, which differ
    /// between two equal dialogs.
    private func text(_ dialog: IntentDialog) -> String {
        let reflection = String(reflecting: dialog)
        return reflection.firstMatch(of: /key: "([^"]+)"/)?.1.description ?? reflection
    }

    /// The dialog inside an intent result. `ProvidesDialog` has no public accessor, so it is read
    /// from the result's reflection.
    private func dialog(of result: some ProvidesDialog) -> String {
        for child in Mirror(reflecting: result).children where child.label == "dialog" {
            if let dialog = child.value as? IntentDialog { return text(dialog) }
        }
        return "no dialog in: \(String(reflecting: result))"
    }

    @Test("Next turn without a battle says so, as master and as player", arguments: [true, false])
    func nextTurnWithoutBattle(master: Bool) async throws {
        let root = try await makeRoot(master: master)
        var intent = NextTurnIntent()
        intent.root = root

        let result = try await intent.perform()

        #expect(dialog(of: result) == text(GameIntentDialog.noBattle))
    }

    @Test("Next round without a battle says so", arguments: [true, false])
    func nextRoundWithoutBattle(master: Bool) async throws {
        let root = try await makeRoot(master: master)
        var intent = NextRoundIntent()
        intent.root = root

        let result = try await intent.perform()

        #expect(dialog(of: result) == text(GameIntentDialog.noBattle))
    }

    @Test("End battle without a battle says so before it asks for a confirmation", arguments: [true, false])
    func endBattleWithoutBattle(master: Bool) async throws {
        let root = try await makeRoot(master: master)
        var intent = EndBattleIntent()
        intent.root = root

        let result = try await intent.perform()

        #expect(dialog(of: result) == text(GameIntentDialog.noBattle))
    }

    @Test("Stop game with no running game says so and changes no flags")
    func stopGameWithoutGame() async throws {
        let root = try await makeRoot(master: true, started: false)
        var intent = StopGameIntent()
        intent.root = root
        var flagChanges = 0
        let previous = IntentGameContext.setGameState
        IntentGameContext.setGameState = { _, _ in flagChanges += 1 }
        defer { IntentGameContext.setGameState = previous }

        let result = try await intent.perform()

        #expect(dialog(of: result) != text(GameIntentDialog.masterOnly))
        #expect(flagChanges == 0)
    }

    @Test("A player cannot stop the game of the master")
    func playerCannotStopTheGame() async throws {
        let root = try await makeRoot(master: false)
        var intent = StopGameIntent()
        intent.root = root
        var flagChanges = 0
        let previous = IntentGameContext.setGameState
        IntentGameContext.setGameState = { _, _ in flagChanges += 1 }
        defer { IntentGameContext.setGameState = previous }

        let result = try await intent.perform()

        #expect(dialog(of: result) == text(GameIntentDialog.masterOnly))
        #expect(flagChanges == 0)
        #expect(root.gameModel.gameConfig.state == .started, "the player's game is still running")
    }

    @Test("The Control Center's next turn does nothing without a battle")
    func controlCenterNextTurnWithoutBattle() async throws {
        let root = try await makeRoot(master: true)

        #expect(!root.nextTurn())
    }

    @Test("The dialogs of the three situations are different texts")
    func dialogsDiffer() {
        let texts = [GameIntentDialog.noBattle, GameIntentDialog.masterOnly, GameIntentDialog.nobodyCanAct].map(text)

        #expect(Set(texts).count == 3)
    }
}
#endif
#endif

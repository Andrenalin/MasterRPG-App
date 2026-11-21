// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Testing

@testable import GameRPG

@Suite("Game table auto open")
struct GameTableAutoOpenPolicyTests {
    private func shouldOpen(
        running: Bool = true,
        stopping: Bool = false,
        state: GameState = .started,
        table: ScenesManager.SceneState = .closed,
        alreadyOpened: Bool = false
    ) -> Bool {
        GameTableAutoOpenPolicy.shouldOpen(
            isGameRunning: running, isStopping: stopping, gameState: state,
            tableSceneState: table, alreadyOpened: alreadyOpened
        )
    }

    @Test("A started game with a closed table opens it")
    func opensClosedTable() {
        #expect(shouldOpen())
        #expect(shouldOpen(table: .closing))
    }

    @Test("Nothing opens while the game is not running or being quit")
    func needsRunningGame() {
        #expect(!shouldOpen(running: false))
        #expect(!shouldOpen(stopping: true))
        #expect(!shouldOpen(state: .stopped))
    }

    @Test("An open or opening table is left alone")
    func leavesOpenTable() {
        #expect(!shouldOpen(table: .opened))
        #expect(!shouldOpen(table: .opening))
    }

    @Test("A table the screen already opened and the user closed stays closed")
    func oneShot() {
        #expect(!shouldOpen(alreadyOpened: true))
    }
}
#endif

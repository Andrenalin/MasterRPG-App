// @copyright André Trettin

#if canImport(Testing)
#if !os(tvOS)
import CoreRPG
import Foundation
import Testing

@testable import AdventureRPG
@testable import GameRPG

/// CODE_AUDIT §5.1: the Siri / Shortcuts "Start Adventure Game" intent used to put every module
/// into game mode without a started game (every later edit then went to game memory only and was
/// lost at relaunch) and ignored the chosen adventure. It now only chooses the adventure through
/// the hook the game root installs on the adventure root, and the game master starts the game.
@Suite("Game adventure selection", .serialized)
@MainActor
struct GameAdventureSelectionTests {
    private let storageKey = GameStorageKeys.lastAdventureUUID

    /// Runs `body` and puts the stored last adventure back, so no test leaks into the others or
    /// into the app's own defaults.
    private func preservingStoredAdventure<Result>(_ body: () async throws -> Result) async rethrows -> Result {
        let stored = UserDefaults.standard.object(forKey: storageKey)
        defer {
            if let stored {
                UserDefaults.standard.set(stored, forKey: storageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: storageKey)
            }
        }
        return try await body()
    }

    private func isInGameMode(_ root: GameRoot) -> Bool {
        root.adventureRoot.itemController.itemDataModel.isGameMode
            || root.adventureRoot.siblingModuleRoots.contains { $0.itemControllable.itemDataModel.isGameMode }
    }

    @Test("The game root installs the hook, and choosing an adventure selects it without entering game mode")
    func choosingSelectsWithoutGameMode() async throws {
        try await preservingStoredAdventure {
            let root = try await MockRoot.createGameRoot()
            let adventureId = UUID()

            let hook = try #require(root.adventureRoot.selectAdventureForGame)
            let isChosen = hook(adventureId)

            #expect(isChosen)
            #expect(root.gameModel.selectedAdventure == adventureId)
            #expect(UserDefaults.standard.string(forKey: storageKey) == adventureId.uuidString)
            #expect(!isInGameMode(root), "Choosing an adventure must not put any module into game mode.")
            #expect(root.gameModel.gameConfig.state == .stopped)
        }
    }

    @Test("Choosing a second adventure replaces the first")
    func choosingTwiceKeepsTheLast() async throws {
        try await preservingStoredAdventure {
            let root = try await MockRoot.createGameRoot()
            let first = UUID()
            let second = UUID()

            #expect(root.selectAdventureForGame(first))
            #expect(root.selectAdventureForGame(second))

            #expect(root.gameModel.selectedAdventure == second)
            #expect(UserDefaults.standard.string(forKey: storageKey) == second.uuidString)
        }
    }

    @Test("Nothing changes while a game is running", arguments: [GameState.started, GameState.prepare])
    func refusedWhileGameIsRunning(state: GameState) async throws {
        try await preservingStoredAdventure {
            let root = try await MockRoot.createGameRoot()
            let current = UUID()
            #expect(root.selectAdventureForGame(current))
            let masterId = UUID()
            root.gameModel.gameConfig = GameConfigModel(
                id: masterId,
                state: state,
                master: MasterGameModel(id: masterId, type: .master, name: "Master")
            )

            let isChosen = root.selectAdventureForGame(UUID())

            #expect(!isChosen)
            #expect(root.gameModel.selectedAdventure == current)
            #expect(UserDefaults.standard.string(forKey: storageKey) == current.uuidString)
        }
    }

    @Test("Nothing changes while the master start is running")
    func refusedWhileMasterIsStarting() async throws {
        try await preservingStoredAdventure {
            let root = try await MockRoot.createGameRoot()
            let current = UUID()
            #expect(root.selectAdventureForGame(current))
            root.isStartingMaster = true

            #expect(!root.selectAdventureForGame(UUID()))
            #expect(root.gameModel.selectedAdventure == current)
        }
    }
}
#endif
#endif

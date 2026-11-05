// @copyright André Trettin

#if canImport(Testing)
import AdventureRPG
import CoreRPG
import Foundation
import Testing

@testable import CharacterRPG
@testable import GameRPG
@testable import MapRPG

@Suite("Table players in a running game")
@MainActor
struct TablePlayersTests {
    @Test("A table player gets a player pin until a joined player takes the Character over")
    func tablePlayerPinLifecycle() async throws {
        let env = try await PlayerMasterControllerTestEnvironment.create()
        let root = env.masterRoot
        root.gameModel.masterController = env.master
        let heroId = UUID()
        root.characterRoot.itemController.replace(model: ValueModel(id: heroId, name: "Hero"), isInsert: true)
        let adventure = AdventureModel.empty(UUID())
        adventure.name = "Journey"
        root.adventureRoot.itemControllable.replace(model: adventure, isInsert: true)
        root.gameModel.gameConfig.master.adventureId = adventure.id

        root.updateTablePlayers([TablePlayerModel(characterId: heroId)])
        await env.master.resetPlayers()

        let tablePlayer = try #require(root.gameModel.tablePlayers.first)
        let playerPins = root.mapRoot.gameController.mapGameModel.playerPins
        #expect(playerPins.map(\.id) == [tablePlayer.id])
        let pin = try #require(playerPins.first)
        #expect(pin.isPlayer)
        #expect(pin.characterId == heroId)
        #expect(pin.name == "Hero")
        #expect(pin.players == [tablePlayer.id])
        // Pins only: a table player is no roster player, so no dice, controls or deliveries.
        #expect(root.gameModel.gameRoster.players.isEmpty)
        #expect(root.gameModel.gameControl.controls.isEmpty)
        // Saved with the adventure.
        #expect(root.adventureRoot.adventureGameControllable.tablePlayers(for: adventure.id) == root.gameModel.tablePlayers)

        let annaId = UUID()
        root.gameModel.gameRoster.players = [PlayerGameModel(id: annaId, type: .player, name: "Anna", characterId: heroId)]
        await env.master.resetPlayers()
        #expect(root.mapRoot.gameController.mapGameModel.playerPins.map(\.id) == [annaId])

        root.gameModel.gameRoster.players = []
        await env.master.resetPlayers()
        #expect(root.mapRoot.gameController.mapGameModel.playerPins.map(\.id) == [tablePlayer.id])

        var disabled = tablePlayer
        disabled.isEnabled = false
        root.updateTablePlayers([disabled])
        await env.master.resetPlayers()
        #expect(root.mapRoot.gameController.mapGameModel.playerPins.isEmpty)
        #expect(root.adventureRoot.adventureGameControllable.tablePlayers(for: adventure.id) == [disabled])
    }

    @Test("The game master's pin controllers reach the pins, for connected devices only")
    func pinControllersReachThePins() async throws {
        let env = try await PlayerMasterControllerTestEnvironment.create()
        let root = env.masterRoot
        root.gameModel.masterController = env.master
        let heroId = UUID()
        root.characterRoot.itemController.replace(model: ValueModel(id: heroId, name: "Hero"), isInsert: true)
        let observer = PlayerGameModel(id: UUID(), type: .observer, name: "Observer")
        root.gameModel.gameRoster.players = [observer]
        root.gameModel.tablePlayers = [TablePlayerModel(characterId: heroId)]
        let tablePinId = try #require(root.gameModel.tablePlayers.first?.id)
        let reconnectingId = UUID()

        root.setPinController(observer.id, for: tablePinId, isEnabled: true)
        root.setPinController(reconnectingId, for: tablePinId, isEnabled: true)
        await env.master.resetPlayers()

        var pin = try #require(root.mapRoot.gameController.mapGameModel.playerPins.first { $0.id == tablePinId })
        #expect(pin.players == [tablePinId, observer.id])
        #expect(pin.isControlled(by: observer.id))
        // Kept for the session, so the device gets the pin back when it reconnects.
        #expect(root.gameModel.pinControllers[tablePinId] == [observer.id, reconnectingId])

        root.setPinController(observer.id, for: tablePinId, isEnabled: false)
        await env.master.resetPlayers()
        pin = try #require(root.mapRoot.gameController.mapGameModel.playerPins.first { $0.id == tablePinId })
        #expect(pin.players == [tablePinId])
    }

    @Test("The panel adds, enables and removes table players")
    func panelEdits() {
        let store = TablePlayersStore()
        let sut = TablePlayersModel {
            store.players
        } update: { players in
            store.players = players
            store.updates += 1
        }
        let heroId = UUID()
        let mageId = UUID()

        sut.startPicking()
        #expect(sut.isPicking)
        sut.selectionModel.toggleSelection(itemId: heroId, entryId: nil, isCollection: false)
        sut.selectionModel.toggleSelection(itemId: mageId, entryId: nil, isCollection: false)
        sut.addPicked()
        #expect(!sut.isPicking)
        #expect(store.players.map(\.characterId) == [heroId, mageId])
        #expect(store.players.allSatisfy { $0.isEnabled })

        sut.startPicking()
        #expect(sut.selectionModel.selection.isEmpty)
        sut.selectionModel.toggleSelection(itemId: heroId, entryId: nil, isCollection: false)
        sut.addPicked()
        #expect(store.players.count == 2)
        #expect(store.updates == 1)

        sut.setEnabled(false, id: store.players[0].id)
        #expect(!store.players[0].isEnabled)
        sut.setEnabled(false, id: store.players[0].id)
        #expect(store.updates == 2)

        sut.remove(id: store.players[0].id)
        #expect(store.players.map(\.characterId) == [mageId])
        sut.remove(atOffsets: IndexSet(integer: 0))
        #expect(store.players.isEmpty)

        sut.startPicking()
        sut.cancelPicking()
        #expect(!sut.isPicking)
        #expect(store.updates == 4)
    }
}

@MainActor
private final class TablePlayersStore {
    var players: [TablePlayerModel] = []
    var updates = 0
}
#endif

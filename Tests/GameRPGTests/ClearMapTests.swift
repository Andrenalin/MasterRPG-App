// @copyright André Trettin

#if canImport(Testing)
import Foundation
import RPGResourcesDebug
import Testing

@testable import CoreRPG
@testable import GameRPG
@testable import MapRPG

@Suite("Clear Map")
@MainActor
struct ClearMapTests {
    private static func masterConfig() -> GameConfigModel {
        let id = UUID()
        return GameConfigModel(id: id, state: .started, master: MasterGameModel(id: id, type: .master, name: "Game Master"))
    }

    private static func clearMessage(counter: Int, mapId: UUID, config: GameConfigModel) -> GameNetworkModel {
        GameNetworkModel(
            counter: counter,
            proxyCounter: 0,
            type: .reveal,
            subType: .show,
            gameConfig: config,
            data: NetworkCodableDataType(id: mapId, type: .none, version: 0)
        )
    }

    @Test("The model keeps its items while the current one is cleared; showing it again ends the clear")
    func modelKeepsItems() {
        let dataModel = ItemDataModel()
        let model = ItemGameModel(itemDataModel: dataModel)
        let first = UUID()
        let second = UUID()
        dataModel.gameItems = [first, second]

        model.clearCurrent()
        #expect(model.currentItemId == nil)
        #expect(dataModel.gameItems == [first, second])

        // Storing another item without showing it keeps the screen clear.
        dataModel.gameItems.append(UUID())
        #expect(model.currentItemId == nil)

        // The same item shown again is current once more, though it is already first.
        #expect(model.moveToFront(itemId: first))
        #expect(model.currentItemId == first)

        model.clearCurrent()
        dataModel.gameItems.insert(second, at: 0)
        #expect(model.currentItemId == second)
    }

    @Test("A player clears the map the game master clears; the map's game copy stays")
    func playerClearsMap() async throws {
        let env = try await PlayerControllerTestEnvironment.create()
        let map = MapModel(id: UUID(), name: "Dungeon")
        env.root.mapRoot.gameController.setGame(item: map.copy(), itemId: map.id)
        let player = env.playerController
        player.gameModel.setGameUpdateType(.map)
        #expect(env.root.mapRoot.gameControllable.gameModel.currentItemId == map.id)

        let response = try await player.handle(Self.clearMessage(counter: 5, mapId: map.id, config: Self.masterConfig()))

        #expect(response == nil)
        #expect(env.root.mapRoot.gameControllable.gameModel.currentItemId == nil)
        #expect(env.root.mapRoot.gameControllable.gameModel.itemData[map.id] != nil)
        #expect(player.gameModel.gameUpdateType == .none)
    }

    @Test("A clear sent by a player does nothing")
    func playerMessageIgnored() async throws {
        let env = try await PlayerControllerTestEnvironment.create()
        let map = MapModel(id: UUID(), name: "Dungeon")
        env.root.mapRoot.gameController.setGame(item: map.copy(), itemId: map.id)
        env.playerController.gameModel.setGameUpdateType(.map)

        var message = Self.clearMessage(counter: 5, mapId: map.id, config: Self.masterConfig())
        message.sender.role = .player
        _ = try await env.playerController.handle(message)

        #expect(env.root.mapRoot.gameControllable.gameModel.currentItemId == map.id)
        #expect(env.playerController.gameModel.gameUpdateType == .map)
    }

    @Test("A clear is the newest show: an older map reveal arriving later is stale")
    func clearOrdersWithShows() {
        let model = PlayerControllerModel()
        let mapId = UUID()
        model.markPresentation(counter: 6, module: .none, itemId: mapId)

        #expect(!model.isCurrentPresentation(counter: 4, module: .map, itemId: mapId))
        #expect(model.isCurrentPresentation(counter: 7, module: .map, itemId: mapId))
    }
}
#endif

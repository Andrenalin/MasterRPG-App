// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Network
import RPGResourcesDebug
import Testing

@testable import CoreRPG
@testable import GameRPG
import PhotoRPG
import AdventureRPG

final class PlayerControllerTests {
    private var sut: PlayerController!
    private var root: GameRoot!
    private var gameConfigModel: GameConfigModel!

    private var masterDeleagteMock: MasterNetworkStoreDelegateMock!
    private var playerDelegateMock: PlayerNetworkStoreDelegateMock!
    private var masterStoreAbstractionMock: MasterNetworkControllableMock!
    private var playerStoreAbstractionMock: PlayerStoreAbstractionMock!

    private var networkMock: NetworkController!

    func setUp() async throws {
        masterDeleagteMock = MasterNetworkStoreDelegateMock()
        playerDelegateMock = PlayerNetworkStoreDelegateMock()
        let masterMock = await MasterNetworkControllableMock()
        let playerMock = await PlayerStoreAbstractionMock()

        networkMock = await NetworkController(name: "Hello Test", masterBuilder: { _, _ in
            masterMock
        }, playerBuilder: { _, _ in
            playerMock
        })
        await networkMock.model.setMaster(delegate: masterDeleagteMock)
        await networkMock.model.setPlayer(delegate: playerDelegateMock)
        masterStoreAbstractionMock = masterMock
        playerStoreAbstractionMock = playerMock
        root = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: root.adventureRoot)
        try await MockRoot.resetGameController(for: root)
        
        root.networkStore = networkMock
        let playerId = UUID()
        gameConfigModel = GameConfigModel(id: playerId, state: .started, master: .empty, players: [PlayerGameModel(id: playerId, type: .player, name: "AndrenalinPlayer")], controls: [])
        await root.gameModel.reset(gameConfig: gameConfigModel)
        
        sut = await PlayerController(root: root, asGameMaster: false)
    }

    @Test func handlePhoto() async throws {
        try await setUp()
        try await MockRoot.importTestData(into: root.adventureRoot)
        
        await root.adventureRoot.startGame()

        await #expect(root.photoRoot.itemControllable.itemDataModel.items.count == 27)
        let itemId = await root.photoRoot.itemControllable.itemDataModel.items[0]
        let netData = try await root.photoRoot.gameControllable.createGameData(for: itemId)
        let netId = await root.photoRoot.gameControllable.share(id: itemId)
        var gameNetworkModel = GameNetworkModel(version: 1, counter: 1, proxyCounter: 0, type: .reveal, subType: .show, gameConfig: gameConfigModel, data: netData)
        
        var result = try await sut.handle(gameNetworkModel)
        #expect(result?.subType == .ok)
        await #expect(root.photoRoot.gameControllable.currentId == itemId)

        await root.photoRoot.gameControllable.reset()
        await #expect(root.photoRoot.gameControllable.currentId != itemId)
        let item = await root.photoRoot.itemControllable.item(for: itemId)
        await root.photoRoot.itemControllable.itemDataModel.resetModel(id: itemId)

        gameNetworkModel = GameNetworkModel(version: 1, counter: 1, proxyCounter: 0, type: .reveal, subType: .show, gameConfig: gameConfigModel, data: netId)
        result = try await sut.handle(gameNetworkModel)
        #expect(result?.subType == .show)
        await #expect(root.photoRoot.gameControllable.currentId != itemId)

        gameNetworkModel = GameNetworkModel(version: 1, counter: 1, proxyCounter: 0, type: .reveal, subType: .show, gameConfig: gameConfigModel, data: netData)
        result = try await sut.handle(gameNetworkModel)
        #expect(result?.subType == .ok)
        await #expect(root.photoRoot.gameControllable.currentId == itemId)
        await #expect(root.photoRoot.itemControllable.item(for: itemId) != nil)
        await #expect(root.photoRoot.itemControllable.item(for: itemId)?.name == item?.name)
    }
}
#endif

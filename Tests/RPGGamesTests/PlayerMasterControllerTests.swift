// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import GameRPG

@testable import DiceRPG
@testable import AudioRPG
@testable import MapRPG
@testable import PhotoRPG
@testable import SpaceRPG
@testable import TableRPG
@testable import CharacterRPG

final class PlayerMasterControllerTests {
    private var sut: MasterController!
    private var rootSut: GameRoot!
    private var gameConfigModelSut: GameConfigModel!

    private var sutPlayer: PlayerController!
    private var rootPlayer: GameRoot!
    private var gameConfigModelPlayer: GameConfigModel!

    private var masterDeleagteMock: MasterNetworkStoreDelegateMock!
    private var playerDelegateMock: PlayerNetworkStoreDelegateMock!
    private var masterStoreAbstractionMock: MasterNetworkControllableMock!
    private var playerStoreAbstractionMock: PlayerStoreAbstractionMock!
    private var networkMock: NetworkController!
    private var networkProxyMock: NetworkProxyController!

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

        networkProxyMock = await NetworkProxyController(name: "Hello Test", masterBuilder: { _, _ in
            masterMock
        }, playerBuilder: { _, _ in
            playerMock
        })

        rootSut = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: rootSut.adventureRoot)
        try await MockRoot.resetGameController(for: rootSut)
        rootSut.networkStore = networkMock
        rootSut.networkProxyStore = networkProxyMock
        let masterId = UUID()
        gameConfigModelSut = GameConfigModel(id: masterId, state: .started, master: MasterGameModel(id: masterId, type: .master, name: "Andrenalin"), players: [], controls: [])
        await rootSut.gameModel.reset(gameConfig: gameConfigModelSut)
        sut = await MasterController(root: rootSut, asProxy: false)

        rootPlayer = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: rootPlayer.adventureRoot)
        try await MockRoot.resetGameController(for: rootPlayer)
        rootPlayer.networkStore = networkMock

        let playerId = UUID()
        gameConfigModelPlayer = GameConfigModel(id: playerId, state: .started, master: .empty, players: [PlayerGameModel(id: playerId, type: .player, name: "AndrenalinPlayer")], controls: [])
        await rootPlayer.gameModel.reset(gameConfig: gameConfigModelPlayer)
        sutPlayer = await PlayerController(root: rootPlayer, asGameMaster: false)
    }
    
    @Test func handleAudio() async throws {
        try await setUp()
        try await MockRoot.importTestData(into: rootPlayer.adventureRoot, name: ResourcesDebug.audioTestData, itemCounter: 0)
        await #expect(rootPlayer.audioRoot.itemController.itemDataModel.items.count == 2)

        // send show audio
        let audioId = await rootPlayer.audioRoot.itemController.itemDataModel.items[1]
        let version = await rootPlayer.audioRoot.itemController.itemOrEmpty(for: audioId).version
        await #expect(rootPlayer.audioRoot.itemController.itemOrEmpty(for: audioId).entries.isEmpty)
        await #expect(rootPlayer.audioRoot.gameController.currentId != audioId)
        let audioShareData = try await rootPlayer.audioRoot.gameController.createGameData(for: audioId)
        await sutPlayer.game(message: audioShareData, actionType: .generic)
        let sendedAudioData = playerStoreAbstractionMock.requestData as? GameNetworkModel
        #expect(nil != sendedAudioData)

        let result = try await sut.handle(sendedAudioData!)
        #expect(nil == result)
        let resendAudioData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(resendAudioData!.type == .reveal)
        #expect(resendAudioData!.subType == .show)
        #expect(resendAudioData!.data.type == .audio)
        await #expect(rootSut.audioRoot.gameController.currentId == audioId)
        await #expect(rootSut.audioRoot.gameController.gameItem(for: audioId).version == version)
        await #expect(rootSut.audioRoot.itemController.itemDataModel.items.count == 1)
        await #expect(rootPlayer.audioRoot.gameController.currentId != audioId)
        
        let playerResult = try await sutPlayer.handle(resendAudioData!)
        #expect(nil != playerResult)
        #expect(playerResult!.subType == .ok)
        await #expect(rootPlayer.audioRoot.gameController.currentId == audioId)
        await #expect(rootPlayer.audioRoot.gameController.gameItem(for: audioId).version == version)
        await #expect(rootPlayer.audioRoot.itemController.itemDataModel.items.count == 2)
    }

    @Test func handlePhoto() async throws {
        try await setUp()
        try await MockRoot.importTestData(into: rootPlayer.adventureRoot, name: ResourcesDebug.photoTestData, itemCounter: 0)
        await #expect(rootPlayer.photoRoot.itemController.itemDataModel.items.count == 3)

        // send show photo
        let photoId = await rootPlayer.photoRoot.itemController.itemDataModel.items[0]
        let version = await rootPlayer.photoRoot.itemController.itemOrEmpty(for: photoId).version
        await #expect(rootPlayer.photoRoot.gameController.currentId != photoId)
        let photoShareData = try await rootPlayer.photoRoot.gameController.createGameData(for: photoId)
        await sutPlayer.game(message: photoShareData, actionType: .generic)
        let sendedPhotoData = playerStoreAbstractionMock.requestData as? GameNetworkModel
        #expect(nil != sendedPhotoData)

        let result = try await sut.handle(sendedPhotoData!)
        #expect(nil == result)
        let resendPhotoData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(resendPhotoData!.type == .reveal)
        #expect(resendPhotoData!.subType == .show)
        #expect(resendPhotoData!.data.type == .photo)
        await #expect(rootSut.photoRoot.gameController.currentId == photoId)
        await #expect(rootSut.photoRoot.gameController.gameItem(for: photoId).version == version)
        await #expect(rootSut.photoRoot.itemController.itemDataModel.items.count == 1)
        await #expect(rootPlayer.photoRoot.gameController.currentId != photoId)

        let playerResult = try await sutPlayer.handle(resendPhotoData!)
        #expect(nil != playerResult)
        #expect(playerResult!.subType == .ok)
        await #expect(rootPlayer.photoRoot.gameController.currentId == photoId)
        await #expect(rootPlayer.photoRoot.gameController.gameItem(for: photoId).version == version)
        await #expect(rootPlayer.photoRoot.itemController.itemDataModel.items.count == 3)
    }

    @Test func handleSapce() async throws {
        try await setUp()
        try await MockRoot.importTestData(into: rootPlayer.adventureRoot, name: ResourcesDebug.spaceTestData, itemCounter: 0)
        await #expect(rootPlayer.spaceRoot.itemController.itemDataModel.items.count == 1)

        // send show space
        let spaceId = await rootPlayer.spaceRoot.itemController.itemDataModel.items[0]
        let version = await rootPlayer.spaceRoot.itemController.itemOrEmpty(for: spaceId).version
        await #expect(rootPlayer.spaceRoot.gameController.currentId != spaceId)
        let spaceShareData = try await rootPlayer.spaceRoot.gameController.createGameData(for: spaceId)
        await sutPlayer.game(message: spaceShareData, actionType: .generic)
        let sendedSpaceData = playerStoreAbstractionMock.requestData as? GameNetworkModel
        #expect(nil != sendedSpaceData)

        let result = try await sut.handle(sendedSpaceData!)
        #expect(nil == result)
        let resendSpaceData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(resendSpaceData!.type == .reveal)
        #expect(resendSpaceData!.subType == .show)
        #expect(resendSpaceData!.data.type == .space)
        await #expect(rootSut.spaceRoot.gameController.currentId == spaceId)
        await #expect(rootSut.spaceRoot.gameController.gameItem(for: spaceId).version == version)
        await #expect(rootSut.spaceRoot.itemController.itemDataModel.items.count == 1)
        await #expect(rootPlayer.spaceRoot.gameController.currentId != spaceId)

        let playerResult = try await sutPlayer.handle(resendSpaceData!)
        #expect(nil != playerResult)
        #expect(playerResult!.subType == .ok)
        await #expect(rootPlayer.spaceRoot.gameController.currentId == spaceId)
        await #expect(rootPlayer.spaceRoot.gameController.gameItem(for: spaceId).version == version)
        await #expect(rootPlayer.spaceRoot.itemController.itemDataModel.items.count == 1)
    }

    @Test func handleCharacterUpdate() async throws {
        try await setUp()
        try await MockRoot.importTestData(into: rootPlayer.adventureRoot)
        await #expect(rootPlayer.valueRoot.itemController.itemDataModel.items.count == 13)

        // send update Character
        let characterId = await rootPlayer.valueRoot.itemController.itemDataModel.items[1]
        var master = await rootSut.gameModel.gameConfig.master
        master.characterId = characterId
        await rootSut.gameModel.reset(master: master)
        let photoId = await rootPlayer.valueRoot.itemController.itemOrEmpty(for: characterId).photoId
        #expect(nil != photoId)
        
        let characterData = try? await rootPlayer.valueRoot.gameControllable.createGameData(for: characterId)
        #expect(nil != characterData)
        await sutPlayer.send(counter: 0, type: .update, subType: .store, updated: characterData!, useJournal: true)
        let sendedCharacterData = playerStoreAbstractionMock.requestData as? GameNetworkModel
        #expect(nil != sendedCharacterData)

        var result = try await sut.handle(sendedCharacterData!)
        #expect(nil == result)
        await #expect(rootSut.valueRoot.itemController.itemDataModel.items.count == 6)
        await #expect(rootSut.photoRoot.itemController.itemDataModel.items.contains(photoId!))
        
        result = try await sut.handle(sendedCharacterData!)
        #expect(nil == result)
        await #expect(rootSut.valueRoot.itemController.itemDataModel.items.count == 6)
        await #expect(rootSut.photoRoot.itemController.itemDataModel.items.contains(photoId!))
    }
}
#endif

// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import GameRPG

@testable import AdventureRPG
@testable import DiceRPG
@testable import AudioRPG
@testable import MapRPG
@testable import PdfRPG
@testable import PhotoRPG
@testable import SpaceRPG
@testable import TableRPG
@testable import CharacterRPG
@testable import WeatherRPG

@MainActor
final class MasterPlayerControllerTests {
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
    private var networkMock: GameNetworkController!
    private var networkProxyMock: GameNetworkController!

    func setUp() async throws {
        masterDeleagteMock = MasterNetworkStoreDelegateMock()
        playerDelegateMock = PlayerNetworkStoreDelegateMock()
        let masterMock = await MasterNetworkControllableMock()
        let playerMock = await PlayerStoreAbstractionMock()

        networkMock = await GameNetworkController(name: "Hello Test", proxy: false, masterBuilder: { _, _ in
            masterMock
        }, playerBuilder: { _, _ in
            playerMock
        })
        await networkMock.model.setMasterDelegate(masterDeleagteMock)
        await networkMock.model.setPlayerDelegate(playerDelegateMock)
        masterStoreAbstractionMock = masterMock
        playerStoreAbstractionMock = playerMock

        networkProxyMock = await GameNetworkController(name: "Hello Test", proxy: true, masterBuilder: { _, _ in
            masterMock
        }, playerBuilder: { _, _ in
            playerMock
        })

        rootSut = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: rootSut.adventureRoot)
        try await MockRoot.resetGameController(for: rootSut)
        let rootSut = self.rootSut!
        let networkMock = self.networkMock!
        let networkProxyMock = self.networkProxyMock!
        await MainActor.run {
            rootSut.networkStore = networkMock
            rootSut.networkProxyStore = networkProxyMock
        }

        let masterId = UUID()
        gameConfigModelSut = GameConfigModel(id: masterId, state: .started, master: MasterGameModel(id: masterId, type: .master, name: "Andrenalin"))
        await rootSut.gameModel.reset(gameConfig: gameConfigModelSut)
        sut = await MasterController(root: rootSut, asProxy: false)

        rootPlayer = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: rootPlayer.adventureRoot)
        try await MockRoot.resetGameController(for: rootPlayer)

        let rootPlayer = self.rootPlayer!
        await MainActor.run {
            rootPlayer.networkStore = networkMock
        }
        let playerId = UUID()
        gameConfigModelPlayer = GameConfigModel(id: playerId, state: .started, master: .empty)
        await rootPlayer.gameModel.reset(gameConfig: gameConfigModelPlayer, gameRoster: GameRosterModel(players: [PlayerGameModel(id: playerId, type: .player, name: "AndrenalinPlayer")]))
        sutPlayer = await PlayerController(root: rootPlayer, asGameMaster: false)
    }
    
    @Test func handleAudio() async throws {
        try await setUp()
        try await MockRoot.importTestData(into: rootSut.adventureRoot)
        try await MockRoot.importTestData(into: rootSut.adventureRoot, name: ResourcesDebug.audioTestData, itemCounter: 3)
        try await #require(rootSut.audioRoot.itemController.itemDataModel.items.count == 12)

        await rootSut.adventureRoot.startGame()
        await rootPlayer.adventureRoot.startGame()
        
        // send show audio
        let audioId = await rootSut.audioRoot.itemController.itemDataModel.items[1]
        let version = await rootSut.audioRoot.itemController.itemOrEmpty(for: audioId).version
        await #expect(rootSut.audioRoot.itemController.itemOrEmpty(for: audioId).entries.isEmpty)
        let audioShareData = await rootSut.audioRoot.gameController.share(id: audioId)
        await sut.show(for: audioShareData)
        var sendedShowAudioData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(nil != sendedShowAudioData)

        var result = try await sutPlayer.handle(sendedShowAudioData!)
        #expect(nil != result)
        #expect(result!.subType == .show)
        await #expect(rootPlayer.audioRoot.gameController.currentId != audioId)

        let response = try await sut.handle(result!)
        #expect(nil != response)
        #expect(response!.id == audioId)
        #expect(response!.type == .audio)
        #expect(nil != response!.data)
        #expect(response!.version == version)

        await sut.send(type: result!.type, subtype: result!.subType, updated: response!)
        sendedShowAudioData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(nil != sendedShowAudioData)

        result = try await sutPlayer.handle(sendedShowAudioData!)
        #expect(nil != result)
        #expect(result!.subType == .ok)
        await #expect(rootPlayer.audioRoot.gameController.currentId == audioId)
        await #expect(rootPlayer.audioRoot.gameController.gameItem(for: audioId).version == version)
        await #expect(rootPlayer.audioRoot.itemController.itemDataModel.items.count == 1)
    }

    @Test func handleAudioPLayList() async throws {
        try await setUp()
        try await MockRoot.importTestData(into: rootSut.adventureRoot)
        try await MockRoot.importTestData(into: rootSut.adventureRoot, name: ResourcesDebug.audioTestData, itemCounter: 3)
        try await #require(rootSut.audioRoot.itemController.itemDataModel.items.count == 12)

        await rootSut.adventureRoot.startGame()
        await rootPlayer.adventureRoot.startGame()

        // send show audio
        let audioId = await rootSut.audioRoot.itemController.itemDataModel.items[0]
        let subAudioId = await rootSut.audioRoot.itemController.itemDataModel.items[1]
        let version = await rootSut.audioRoot.itemController.itemOrEmpty(for: audioId).version
        
        let audioShareData = await rootSut.audioRoot.gameController.share(id: audioId)
        await sut.show(for: audioShareData)
        var sendedShowAudioData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(nil != sendedShowAudioData)

        await #expect(rootPlayer.audioRoot.itemController.itemDataModel.items.count == 0)
        var result = try await sutPlayer.handle(sendedShowAudioData!)
        #expect(nil != result)
        #expect(result!.subType == .show)
        await #expect(rootPlayer.audioRoot.gameController.currentId != audioId)

        var response = try await sut.handle(result!)
        #expect(nil != response)
        #expect(response!.id == audioId)
        #expect(response!.type == .audio)
        #expect(nil != response!.data)
        #expect(response!.version == version)

        await sut.send(type: result!.type, subtype: result!.subType, updated: response!)
        sendedShowAudioData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(nil != sendedShowAudioData)

        result = try await sutPlayer.handle(sendedShowAudioData!)
        #expect(nil != result)
        #expect(result!.subType == .ok)
        await #expect(rootPlayer.audioRoot.gameController.currentId == audioId)
        await #expect(rootPlayer.audioRoot.gameController.gameItem(for: audioId).version == version)
        await #expect(rootPlayer.audioRoot.itemController.itemDataModel.items.count == 1)

        response = try await sut.handle(result!)
        #expect(nil == response)
        await #expect(rootSut.audioRoot.gameController.gameModel.playerReport(for: audioId).sorted() == [gameConfigModelPlayer.id, gameConfigModelSut.id].sorted())
        await #expect(rootSut.audioRoot.gameController.gameModel.playerReport(for: subAudioId).sorted() == [gameConfigModelPlayer.id, gameConfigModelSut.id].sorted())

        let playData = await rootSut.audioRoot.gameController.requestPlay(id: audioId)
        await sut.game(message: playData, actionType: .playAudio)
        let sendedPlayAudioData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(nil != sendedPlayAudioData)

        result = try await sutPlayer.handle(sendedPlayAudioData!)
        #expect(nil == result)
        try await #require(rootPlayer.audioRoot.audioController.model.playList.count == 2)
        await #expect(rootPlayer.audioRoot.audioController.model.playList[0].id == audioId)
        let audioFirst = await rootSut.audioRoot.itemController.itemDataModel.items[1]
        await #expect(rootPlayer.audioRoot.audioController.model.playList[1].id == audioFirst)
        await #expect(rootPlayer.audioRoot.audioController.model.currentId == audioId)
    }

    @Test func handleDice() async throws {
        try await setUp()
        try await importTestData(into: rootSut)
        try await importDiceTestData(into: rootSut)
        try await #require(rootSut.diceRoot.itemController.itemDataModel.items.count == 15)
        try await importTestData(into: rootPlayer)
        try await importDiceTestData(into: rootPlayer)
        try await #require(rootPlayer.diceRoot.itemController.itemDataModel.items.count == 15)
    
        await rootSut.adventureRoot.startGame()
        await rootPlayer.adventureRoot.startGame()

        // share Dice
        let diceId = await rootSut.diceRoot.itemController.itemDataModel.items[0]
        let name = await rootSut.diceRoot.itemController.itemOrEmpty(for: diceId).name
        #expect(name == "10W20")
        let tableId = await rootSut.tableRoot.itemController.itemDataModel.items[0]
        let resultCategory = ResultCategory(id: tableId, module: .table)
        let diceShareData = await rootSut.diceRoot.gameController.createDiceResult(for: diceId, resultCategory: resultCategory)
        await sut.game(message: diceShareData, actionType: .generic)
        let sendedShowDiceData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(nil != sendedShowDiceData)

        await #expect(rootPlayer.diceRoot.gameController.diceGameModel.playerDice.count == 0)
        let result = try await sutPlayer.handle(sendedShowDiceData!)
        #expect(nil == result)
        await #expect(rootPlayer.diceRoot.gameController.currentId != diceId)
        await #expect(rootPlayer.diceRoot.gameController.diceGameModel.playerDice.count == 1)
        let playerDiceId = await rootPlayer.diceRoot.gameController.gameModel.items[0]
        await #expect(rootPlayer.diceRoot.gameController.diceGameModel.playerDice[0].id == playerDiceId)

        let currentPlayerDice = await rootPlayer.diceRoot.gameController.gameItem(for: playerDiceId)
        #expect(currentPlayerDice.name == "Andrenalin")
        #expect(currentPlayerDice.resultCategory == resultCategory)
        
        let playerDiceShareData = await rootPlayer.diceRoot.gameController.createDiceResult(for: playerDiceId, resultCategory: currentPlayerDice.resultCategory!)
        await sutPlayer.game(message: playerDiceShareData, actionType: .generic)
        let sendedPlayerDiceData = playerStoreAbstractionMock.requestData as? GameNetworkModel
        #expect(nil != sendedPlayerDiceData)

        await #expect(rootSut.diceRoot.gameController.diceGameModel.playerDice.count == 0)
        let tableModel = await rootSut.tableRoot.itemController.itemOrEmpty(for: tableId)
        #expect(nil == tableModel.diceResult)

        let response = try await sut.handle(sendedPlayerDiceData!)
        #expect(nil == response)
        await #expect(rootSut.diceRoot.gameController.currentId != diceId)
        await #expect(rootSut.diceRoot.gameController.diceGameModel.playerDice.count == 1)

        let sendedPlayerDiceId = await rootSut.diceRoot.gameController.gameModel.items[0]
        await #expect(rootSut.diceRoot.gameController.diceGameModel.playerDice[0].id == sendedPlayerDiceId)

        let currentSendedPlayerDice = await rootSut.diceRoot.gameController.gameItem(for: sendedPlayerDiceId)
        #expect(currentSendedPlayerDice.name == "AndrenalinPlayer")
        #expect(currentSendedPlayerDice.resultCategory == resultCategory)
        #expect(nil != tableModel.diceResult)
        
        // 2nd share
        let dice2Id = await rootSut.diceRoot.itemController.itemDataModel.items[1]
        let name2 = await rootSut.diceRoot.itemController.itemOrEmpty(for: dice2Id).name
        #expect(name2 == "3W20")
        let table2Id = await rootSut.tableRoot.itemController.itemDataModel.items[1]
        let result2Category = ResultCategory(id: table2Id, module: .table)
        let dice2ShareData = await rootSut.diceRoot.gameController.createDiceResult(for: dice2Id, resultCategory: result2Category)
        await sut.game(message: dice2ShareData, actionType: .generic)
        let sended2ShowDiceData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(nil != sended2ShowDiceData)

        await #expect(rootPlayer.diceRoot.gameController.diceGameModel.playerDice.count == 1)
        let result2 = try await sutPlayer.handle(sended2ShowDiceData!)
        #expect(nil == result2)
        await #expect(rootPlayer.diceRoot.gameController.currentId != dice2Id)
        await #expect(rootPlayer.diceRoot.gameController.diceGameModel.playerDice.count == 1)
        let playerDice2Id = await rootPlayer.diceRoot.gameController.gameModel.items[0]
        await #expect(rootPlayer.diceRoot.gameController.diceGameModel.playerDice[0].id == playerDice2Id)

        let current2PlayerDice = await rootPlayer.diceRoot.gameController.gameItem(for: playerDice2Id)
        #expect(current2PlayerDice.name == "Andrenalin")
        #expect(current2PlayerDice.resultCategory == result2Category)
        
        let player2DiceShareData = await rootPlayer.diceRoot.gameController.createDiceResult(for: playerDice2Id, resultCategory: current2PlayerDice.resultCategory!)
        await sutPlayer.game(message: player2DiceShareData, actionType: .generic)
        let sended2PlayerDiceData = playerStoreAbstractionMock.requestData as? GameNetworkModel
        #expect(nil != sended2PlayerDiceData)

        await #expect(rootSut.diceRoot.gameController.diceGameModel.playerDice.count == 1)
        let table2Model = await rootSut.tableRoot.itemController.itemOrEmpty(for: table2Id)
        #expect(nil == table2Model.diceResult)

        let response2 = try await sut.handle(sended2PlayerDiceData!)
        #expect(nil == response2)
        await #expect(rootSut.diceRoot.gameController.currentId != dice2Id)
        await #expect(rootSut.diceRoot.gameController.diceGameModel.playerDice.count == 1)

        let sended2PlayerDiceId = await rootSut.diceRoot.gameController.gameModel.items[0]
        await #expect(rootSut.diceRoot.gameController.diceGameModel.playerDice[0].id == sended2PlayerDiceId)

        let current2SendedPlayerDice = await rootSut.diceRoot.gameController.gameItem(for: sended2PlayerDiceId)
        #expect(current2SendedPlayerDice.name == "AndrenalinPlayer")
        #expect(current2SendedPlayerDice.resultCategory == result2Category)
        #expect(nil != table2Model.diceResult)
    }

    @Test func handleMap() async throws {
        try await setUp()
        try await importTestData(into: rootSut)
        try await #require(rootSut.mapRoot.itemController.itemDataModel.items.count == 3)
        
        await rootSut.adventureRoot.startGame()
        await rootPlayer.adventureRoot.startGame()

        // send show map
        let mapId = await rootSut.mapRoot.itemController.itemDataModel.items[0]
        let version = await rootSut.mapRoot.itemController.itemOrEmpty(for: mapId).version
        let photoId = await rootSut.mapRoot.itemController.itemOrEmpty(for: mapId).photoId
        #expect(nil != photoId)
        let mapShareData = await rootSut.mapRoot.gameController.share(id: mapId)
        await sut.show(for: mapShareData)
        var sendedShowMapData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(nil != sendedShowMapData)

        var result = try await sutPlayer.handle(sendedShowMapData!)
        #expect(nil != result)
        #expect(result!.subType == .show)
        await #expect(rootPlayer.mapRoot.gameController.currentId != mapId)

        let response = try await sut.handle(result!)
        #expect(nil != response)
        #expect(response!.id == mapId)
        #expect(response!.type == .map)
        #expect(nil != response!.data)
        #expect(response!.version == version)

        await sut.send(type: result!.type, subtype: result!.subType, updated: response!)
        sendedShowMapData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(nil != sendedShowMapData)

        result = try await sutPlayer.handle(sendedShowMapData!)
        #expect(nil != result)
        #expect(result!.subType == .ok)
        await #expect(rootPlayer.mapRoot.gameController.currentId == mapId)
        //await #expect(rootPlayer.photoRoot.gameController.gameModel.items.contains(photoId!))
        let playerPhoto1 = await rootPlayer.photoRoot.gameController.gameItem(for: photoId!).version
        let sutPhoto1 = await rootSut.photoRoot.gameController.gameItem(for: photoId!).version
        #expect(playerPhoto1 == sutPhoto1)

        let entry = await rootSut.mapRoot.gameController.gameItem(for: mapId).entries[0]
        #expect(!entry.isShown)
        await rootSut.mapRoot.gameController.gameItem(for: mapId).toggle(entry.id)
        await #expect(rootSut.mapRoot.gameController.gameItem(for: mapId)[entry.id].isShown)
        await sut.game(message: rootSut.mapRoot.gameController.networkMapUpdate(for: mapId), actionType: .mapState)
        let updatedMapData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(nil != updatedMapData)
        await #expect(!rootPlayer.mapRoot.gameController.gameItem(for: mapId).entries[0].isShown)
        
        result = try await sutPlayer.handle(updatedMapData!)
        #expect(nil == result)
        let mapPlayer = await rootPlayer.mapRoot.gameController.gameItem(for: mapId)
        let mapMaster = await rootSut.mapRoot.gameController.gameItem(for: mapId)
        #expect(mapPlayer.entries[0].isShown)
        #expect(mapPlayer.entries == mapMaster.entries)
    }
    
    @Test func handlePhoto() async throws {
        try await setUp()
        try await importTestData(into: rootSut)
        try await importPhotoTestData(into: rootSut)
        try await #require(rootSut.photoRoot.itemController.itemDataModel.items.count == 35)

        await rootSut.adventureRoot.startGame()
        await rootPlayer.adventureRoot.startGame()

        // send show audio
        let photoId = await rootSut.photoRoot.itemController.itemDataModel.items[0]
        let version = await rootSut.photoRoot.itemController.itemOrEmpty(for: photoId).version
        let photoShareData = await rootSut.photoRoot.gameController.share(id: photoId)
        await sut.show(for: photoShareData)
        var sendedShowPhotoData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(nil != sendedShowPhotoData)

        var result = try await sutPlayer.handle(sendedShowPhotoData!)
        #expect(nil != result)
        #expect(result!.subType == .show)
        await #expect(rootPlayer.photoRoot.gameController.currentId != photoId)

        let response = try await sut.handle(result!)
        #expect(nil != response)
        #expect(response!.id == photoId)
        #expect(response!.type == .photo)
        #expect(nil != response!.data)
        #expect(response!.version == version)

        await sut.send(type: result!.type, subtype: result!.subType, updated: response!)
        sendedShowPhotoData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(nil != sendedShowPhotoData)

        result = try await sutPlayer.handle(sendedShowPhotoData!)
        #expect(nil != result)
        #expect(result!.subType == .ok)
        await #expect(rootPlayer.photoRoot.gameController.currentId == photoId)
        await #expect(rootPlayer.photoRoot.gameController.gameItem(for: photoId).version == version)
    }

    @Test func handleSapce() async throws {
        try await setUp()
        try await importTestData(into: rootSut)
        try await importSpaceTestData(into: rootSut)
        try await #require(rootSut.spaceRoot.itemController.itemDataModel.items.count == 1)

        await rootSut.adventureRoot.startGame()
        await rootPlayer.adventureRoot.startGame()

        // send show space
        let spaceId = await rootSut.spaceRoot.itemController.itemDataModel.items[0]
        let version = await rootSut.spaceRoot.itemController.itemOrEmpty(for: spaceId).version
        let spaceShareData = await rootSut.spaceRoot.gameController.share(id: spaceId)
        await sut.show(for: spaceShareData)
        var sendedShowSpaceData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(nil != sendedShowSpaceData)

        var result = try await sutPlayer.handle(sendedShowSpaceData!)
        #expect(nil != result)
        #expect(result!.subType == .show)
        await #expect(rootPlayer.spaceRoot.gameController.currentId != spaceId)

        let response = try await sut.handle(result!)
        #expect(nil != response)
        #expect(response!.id == spaceId)
        #expect(response!.type == .space)
        #expect(nil != response!.data)
        #expect(response!.version == version)

        await sut.send(type: result!.type, subtype: result!.subType, updated: response!)
        sendedShowSpaceData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(nil != sendedShowSpaceData)

        result = try await sutPlayer.handle(sendedShowSpaceData!)
        #expect(nil != result)
        #expect(result!.subType == .ok)
        await #expect(rootPlayer.spaceRoot.gameController.currentId == spaceId)
        await #expect(rootPlayer.spaceRoot.gameController.gameItem(for: spaceId).version == version)
    }

    @Test func handleTable() async throws {
        try await setUp()
        try await importTestData(into: rootSut)
        try await importTableTestData(into: rootSut)
        try await #require(rootSut.tableRoot.itemController.itemDataModel.items.count == 69)

        await rootSut.adventureRoot.startGame()
        await rootPlayer.adventureRoot.startGame()

        // send show table
        let tableId = await rootSut.tableRoot.itemController.itemDataModel.items[0]
        let version = await rootSut.tableRoot.itemController.itemOrEmpty(for: tableId).version
        let tableShareData = await rootSut.tableRoot.gameController.share(id: tableId)
        await sut.show(for: tableShareData)
        var sendedShowTableData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(nil != sendedShowTableData)

        var result = try await sutPlayer.handle(sendedShowTableData!)
        #expect(nil != result)
        #expect(result!.subType == .show)
        await #expect(rootPlayer.tableRoot.gameController.currentId != tableId)

        let response = try await sut.handle(result!)
        #expect(nil != response)
        #expect(response!.id == tableId)
        #expect(response!.type == .table)
        #expect(nil != response!.data)
        #expect(response!.version == version)

        await sut.send(type: result!.type, subtype: result!.subType, updated: response!)
        sendedShowTableData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(nil != sendedShowTableData)

        result = try await sutPlayer.handle(sendedShowTableData!)
        #expect(nil != result)
        #expect(result!.subType == .ok)
        await #expect(rootPlayer.tableRoot.gameController.currentId == tableId)
        await #expect(rootPlayer.tableRoot.gameController.gameItem(for: tableId).version == version)
    }
}

private extension MasterPlayerControllerTests {
    func importTestData(into root: GameRoot) async throws {
        let bundle = ResourcesDebug.bundle
        let url = bundle.url(forResource: ResourcesDebug.adventureTestData, withExtension: "gmz").unsafelyUnwrapped
        let task = await root.adventureRoot.importControllable.importUrl(from: url)
        let _ = try await task.value
    }
    
    func importDiceTestData(into root: GameRoot) async throws {
        let bundle = ResourcesDebug.bundle
        let url = bundle.url(forResource: ResourcesDebug.diceTestData, withExtension: "gmz").unsafelyUnwrapped
        let task = await root.adventureRoot.importControllable.importUrl(from: url)
        let _ = try await task.value
    }
    
    func importPhotoTestData(into root: GameRoot) async throws {
        let bundle = ResourcesDebug.bundle
        let url = bundle.url(forResource: ResourcesDebug.photoTestData, withExtension: "gmz").unsafelyUnwrapped
        let task = await root.adventureRoot.importControllable.importUrl(from: url)
        let _ = try await task.value
    }

    func importSpaceTestData(into root: GameRoot) async throws {
        let bundle = ResourcesDebug.bundle
        let url = bundle.url(forResource: ResourcesDebug.spaceTestData, withExtension: "gmz").unsafelyUnwrapped
        let task = await root.adventureRoot.importControllable.importUrl(from: url)
        let _ = try await task.value
    }

    func importTableTestData(into root: GameRoot) async throws {
        let bundle = ResourcesDebug.bundle
        let url = bundle.url(forResource: ResourcesDebug.tableTestData, withExtension: "gmz").unsafelyUnwrapped
        let task = await root.adventureRoot.importControllable.importUrl(from: url)
        let _ = try await task.value
    }
}
#endif

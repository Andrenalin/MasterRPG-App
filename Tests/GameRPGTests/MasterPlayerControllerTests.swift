// @copyright André Trettin

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
        let masterMock = MasterNetworkControllableMock()
        let playerMock = PlayerStoreAbstractionMock()

        networkMock = GameNetworkController(name: "Hello Test", proxy: false, masterBuilder: { _, _ in
            masterMock
        }, playerBuilder: { _, _ in
            playerMock
        })
        networkMock.model.setMasterDelegate(masterDeleagteMock)
        networkMock.model.setPlayerDelegate(playerDelegateMock)
        masterStoreAbstractionMock = masterMock
        playerStoreAbstractionMock = playerMock

        networkProxyMock = GameNetworkController(name: "Hello Test", proxy: true, masterBuilder: { _, _ in
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
        rootSut.gameModel.reset(gameConfig: gameConfigModelSut)
        sut = MasterController(root: rootSut, asProxy: false)

        rootPlayer = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: rootPlayer.adventureRoot)
        try await MockRoot.resetGameController(for: rootPlayer)

        let rootPlayer = self.rootPlayer!
        await MainActor.run {
            rootPlayer.networkStore = networkMock
        }
        let playerId = UUID()
        gameConfigModelPlayer = GameConfigModel(id: playerId, state: .started, master: .empty)
        rootPlayer.gameModel.reset(gameConfig: gameConfigModelPlayer, gameRoster: GameRosterModel(players: [PlayerGameModel(id: playerId, type: .player, name: "AndrenalinPlayer")]))
        sutPlayer = PlayerController(root: rootPlayer, asGameMaster: false)
    }
    
    @Test func handleAudio() async throws {
        try await setUp()
        try await MockRoot.importTestData(into: rootSut.adventureRoot)
        try await MockRoot.importTestData(into: rootSut.adventureRoot, name: ResourcesDebug.audioTestData, itemCounter: 3)
        try #require(rootSut.audioRoot.itemController.itemDataModel.items.count == 2)

        rootSut.adventureRoot.startGame()
        rootPlayer.adventureRoot.startGame()
        
        // send show audio
        let audioId = rootSut.audioRoot.itemController.itemDataModel.items[1]
        let version = rootSut.audioRoot.itemController.itemOrEmpty(for: audioId).version
        #expect(rootSut.audioRoot.itemController.itemOrEmpty(for: audioId).entries.isEmpty)
        let audioShareData = await rootSut.audioRoot.gameController.share(id: audioId)
        await sut.show(for: audioShareData)
        var sendedShowAudioData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(nil != sendedShowAudioData)

        var result = try await sutPlayer.handle(sendedShowAudioData!)
        #expect(nil != result)
        #expect(result!.subType == .show)
        #expect(await rootPlayer.audioRoot.gameController.currentId != audioId)

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
        #expect(await rootPlayer.audioRoot.gameController.currentId == audioId)
        #expect(rootPlayer.audioRoot.gameController.gameItem(for: audioId).version == version)
        #expect(rootPlayer.audioRoot.itemController.itemDataModel.items.count == 1)
    }

    @Test func handleAudioPLayList() async throws {
        try await setUp()
        try await MockRoot.importTestData(into: rootSut.adventureRoot)
        try await MockRoot.importTestData(into: rootSut.adventureRoot, name: ResourcesDebug.audioTestData, itemCounter: 3)
        try #require(rootSut.audioRoot.itemController.itemDataModel.items.count == 2)

        rootSut.adventureRoot.startGame()
        rootPlayer.adventureRoot.startGame()

        // send show audio
        let audioId = rootSut.audioRoot.itemController.itemDataModel.items[0]
        let subAudioId = rootSut.audioRoot.itemController.itemDataModel.items[1]
        let version = rootSut.audioRoot.itemController.itemOrEmpty(for: audioId).version
        
        let audioShareData = await rootSut.audioRoot.gameController.share(id: audioId)
        await sut.show(for: audioShareData)
        var sendedShowAudioData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(nil != sendedShowAudioData)

        #expect(rootPlayer.audioRoot.itemController.itemDataModel.items.count == 0)
        var result = try await sutPlayer.handle(sendedShowAudioData!)
        #expect(nil != result)
        #expect(result!.subType == .show)
        #expect(await rootPlayer.audioRoot.gameController.currentId != audioId)

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
        #expect(await rootPlayer.audioRoot.gameController.currentId == audioId)
        #expect(rootPlayer.audioRoot.gameController.gameItem(for: audioId).version == version)
        #expect(rootPlayer.audioRoot.itemController.itemDataModel.items.count == 1)

        response = try await sut.handle(result!)
        #expect(nil == response)
        #expect(rootSut.audioRoot.gameController.gameModel.playerReport(for: audioId).sorted() == [gameConfigModelPlayer.id, gameConfigModelSut.id].sorted())
        #expect(rootSut.audioRoot.gameController.gameModel.playerReport(for: subAudioId).sorted() == [gameConfigModelPlayer.id, gameConfigModelSut.id].sorted())

        let playData = rootSut.audioRoot.gameController.requestPlay(id: audioId)
        await sut.game(message: playData, actionType: .playAudio)
        let sendedPlayAudioData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(nil != sendedPlayAudioData)

        result = try await sutPlayer.handle(sendedPlayAudioData!)
        #expect(nil == result)
        try #require(rootPlayer.audioRoot.audioController.model.playList.count == 2)
        #expect(rootPlayer.audioRoot.audioController.model.playList[0].id == audioId)
        let audioFirst = rootSut.audioRoot.itemController.itemDataModel.items[1]
        #expect(rootPlayer.audioRoot.audioController.model.playList[1].id == audioFirst)
        #expect(rootPlayer.audioRoot.audioController.model.currentId == audioId)
    }

    @Test func handleDice() async throws {
        try await setUp()
        try await importTestData(into: rootSut)
        try await importDiceTestData(into: rootSut)
        try #require(rootSut.diceRoot.itemController.itemDataModel.items.count == 15)
        try await importTestData(into: rootPlayer)
        try await importDiceTestData(into: rootPlayer)
        try #require(rootPlayer.diceRoot.itemController.itemDataModel.items.count == 15)
    
        rootSut.adventureRoot.startGame()
        rootPlayer.adventureRoot.startGame()

        // share Dice
        let diceId = rootSut.diceRoot.itemController.itemDataModel.items[0]
        let name = rootSut.diceRoot.itemController.itemOrEmpty(for: diceId).name
        #expect(name == "10W20")
        let tableId = rootSut.tableRoot.itemController.itemDataModel.items[0]
        let resultCategory = ResultCategory(id: tableId, module: .table)
        let diceShareData = await rootSut.diceRoot.gameController.createDiceResult(for: diceId, resultCategory: resultCategory)
        await sut.game(message: diceShareData, actionType: .generic)
        let sendedShowDiceData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(nil != sendedShowDiceData)

        #expect(rootPlayer.diceRoot.gameController.diceGameModel.playerDice.count == 0)
        let result = try await sutPlayer.handle(sendedShowDiceData!)
        #expect(nil == result)
        #expect(await rootPlayer.diceRoot.gameController.currentId != diceId)
        #expect(rootPlayer.diceRoot.gameController.diceGameModel.playerDice.count == 1)
        let playerDiceId = rootPlayer.diceRoot.gameController.gameModel.items[0]
        #expect(rootPlayer.diceRoot.gameController.diceGameModel.playerDice[0].id == playerDiceId)

        let currentPlayerDice = rootPlayer.diceRoot.gameController.gameItem(for: playerDiceId)
        #expect(currentPlayerDice.name == "Andrenalin")
        #expect(currentPlayerDice.resultCategory == resultCategory)
        
        let playerDiceShareData = await rootPlayer.diceRoot.gameController.createDiceResult(for: playerDiceId, resultCategory: currentPlayerDice.resultCategory!)
        await sutPlayer.game(message: playerDiceShareData, actionType: .generic)
        let sendedPlayerDiceData = playerStoreAbstractionMock.requestData as? GameNetworkModel
        #expect(nil != sendedPlayerDiceData)

        #expect(rootSut.diceRoot.gameController.diceGameModel.playerDice.count == 0)
        let tableModel = rootSut.tableRoot.itemController.itemOrEmpty(for: tableId)
        #expect(nil == tableModel.diceResult)

        let response = try await sut.handle(sendedPlayerDiceData!)
        #expect(nil == response)
        #expect(await rootSut.diceRoot.gameController.currentId != diceId)
        #expect(rootSut.diceRoot.gameController.diceGameModel.playerDice.count == 1)

        let sendedPlayerDiceId = rootSut.diceRoot.gameController.gameModel.items[0]
        #expect(rootSut.diceRoot.gameController.diceGameModel.playerDice[0].id == sendedPlayerDiceId)

        let currentSendedPlayerDice = rootSut.diceRoot.gameController.gameItem(for: sendedPlayerDiceId)
        #expect(currentSendedPlayerDice.name == "AndrenalinPlayer")
        #expect(currentSendedPlayerDice.resultCategory == resultCategory)
        #expect(nil != tableModel.diceResult)
        
        // 2nd share
        let dice2Id = rootSut.diceRoot.itemController.itemDataModel.items[1]
        let name2 = rootSut.diceRoot.itemController.itemOrEmpty(for: dice2Id).name
        #expect(name2 == "3W20")
        let table2Id = rootSut.tableRoot.itemController.itemDataModel.items[1]
        let result2Category = ResultCategory(id: table2Id, module: .table)
        let dice2ShareData = await rootSut.diceRoot.gameController.createDiceResult(for: dice2Id, resultCategory: result2Category)
        await sut.game(message: dice2ShareData, actionType: .generic)
        let sended2ShowDiceData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(nil != sended2ShowDiceData)

        #expect(rootPlayer.diceRoot.gameController.diceGameModel.playerDice.count == 1)
        let result2 = try await sutPlayer.handle(sended2ShowDiceData!)
        #expect(nil == result2)
        #expect(await rootPlayer.diceRoot.gameController.currentId != dice2Id)
        #expect(rootPlayer.diceRoot.gameController.diceGameModel.playerDice.count == 1)
        let playerDice2Id = rootPlayer.diceRoot.gameController.gameModel.items[0]
        #expect(rootPlayer.diceRoot.gameController.diceGameModel.playerDice[0].id == playerDice2Id)

        let current2PlayerDice = rootPlayer.diceRoot.gameController.gameItem(for: playerDice2Id)
        #expect(current2PlayerDice.name == "Andrenalin")
        #expect(current2PlayerDice.resultCategory == result2Category)
        
        let player2DiceShareData = await rootPlayer.diceRoot.gameController.createDiceResult(for: playerDice2Id, resultCategory: current2PlayerDice.resultCategory!)
        await sutPlayer.game(message: player2DiceShareData, actionType: .generic)
        let sended2PlayerDiceData = playerStoreAbstractionMock.requestData as? GameNetworkModel
        #expect(nil != sended2PlayerDiceData)

        #expect(rootSut.diceRoot.gameController.diceGameModel.playerDice.count == 1)
        let table2Model = rootSut.tableRoot.itemController.itemOrEmpty(for: table2Id)
        #expect(nil == table2Model.diceResult)

        let response2 = try await sut.handle(sended2PlayerDiceData!)
        #expect(nil == response2)
        #expect(await rootSut.diceRoot.gameController.currentId != dice2Id)
        #expect(rootSut.diceRoot.gameController.diceGameModel.playerDice.count == 1)

        let sended2PlayerDiceId = rootSut.diceRoot.gameController.gameModel.items[0]
        #expect(rootSut.diceRoot.gameController.diceGameModel.playerDice[0].id == sended2PlayerDiceId)

        let current2SendedPlayerDice = rootSut.diceRoot.gameController.gameItem(for: sended2PlayerDiceId)
        #expect(current2SendedPlayerDice.name == "AndrenalinPlayer")
        #expect(current2SendedPlayerDice.resultCategory == result2Category)
        #expect(nil != table2Model.diceResult)
    }

    @Test func handleMap() async throws {
        try await setUp()
        try await importTestData(into: rootSut)
        try #require(rootSut.mapRoot.itemController.itemDataModel.items.count == 3)
        
        rootSut.adventureRoot.startGame()
        rootPlayer.adventureRoot.startGame()

        // send show map
        let mapId = rootSut.mapRoot.itemController.itemDataModel.items[0]
        let version = rootSut.mapRoot.itemController.itemOrEmpty(for: mapId).version
        let photoId = rootSut.mapRoot.itemController.itemOrEmpty(for: mapId).photoId
        #expect(nil != photoId)
        let mapShareData = await rootSut.mapRoot.gameController.share(id: mapId)
        await sut.show(for: mapShareData)
        var sendedShowMapData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(nil != sendedShowMapData)

        var result = try await sutPlayer.handle(sendedShowMapData!)
        #expect(nil != result)
        #expect(result!.subType == .show)
        #expect(await rootPlayer.mapRoot.gameController.currentId != mapId)

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
        #expect(await rootPlayer.mapRoot.gameController.currentId == mapId)
        //#expect(rootPlayer.photoRoot.gameController.gameModel.items.contains(photoId!))
        let playerPhoto1 = rootPlayer.photoRoot.gameController.gameItem(for: photoId!).version
        let sutPhoto1 = rootSut.photoRoot.gameController.gameItem(for: photoId!).version
        #expect(playerPhoto1 == sutPhoto1)

        let entry = rootSut.mapRoot.gameController.gameItem(for: mapId).entries[0]
        #expect(!entry.isShown)
        rootSut.mapRoot.gameController.gameItem(for: mapId).toggle(entry.id)
        #expect(rootSut.mapRoot.gameController.gameItem(for: mapId)[entry.id].isShown)
        await sut.game(message: rootSut.mapRoot.gameController.networkMapUpdate(for: mapId), actionType: .mapState)
        let updatedMapData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(nil != updatedMapData)
        #expect(!rootPlayer.mapRoot.gameController.gameItem(for: mapId).entries[0].isShown)
        
        result = try await sutPlayer.handle(updatedMapData!)
        #expect(nil == result)
        let mapPlayer = rootPlayer.mapRoot.gameController.gameItem(for: mapId)
        let mapMaster = rootSut.mapRoot.gameController.gameItem(for: mapId)
        #expect(mapPlayer.entries[0].isShown)
        #expect(mapPlayer.entries == mapMaster.entries)
    }

    @Test func mapRevealRequestsMapPayloadBeforeChangingPlayerState() async throws {
        try await setUp()
        try await importTestData(into: rootSut)
        try #require(rootSut.mapRoot.itemController.itemDataModel.items.count == 3)

        rootSut.adventureRoot.startGame()
        rootPlayer.adventureRoot.startGame()
        sutPlayer.gameModel.gameUpdateType = .table

        let mapId = rootSut.mapRoot.itemController.itemDataModel.items[0]
        let version = rootSut.mapRoot.itemController.itemOrEmpty(for: mapId).version
        let mapShareData = await rootSut.mapRoot.gameController.share(id: mapId)

        await sut.show(for: mapShareData)
        let idOnlyMapReveal = try #require(masterStoreAbstractionMock.sendResponseData as? GameNetworkModel)
        #expect(idOnlyMapReveal.type == .reveal)
        #expect(idOnlyMapReveal.subType == .show)
        #expect(idOnlyMapReveal.data.id == mapId)
        #expect(idOnlyMapReveal.data.type == .map)
        #expect(idOnlyMapReveal.data.data == nil)

        let fullMapRequest = try #require(try await sutPlayer.handle(idOnlyMapReveal))
        #expect(fullMapRequest.type == .reveal)
        #expect(fullMapRequest.subType == .show)
        #expect(fullMapRequest.data.id == mapId)
        #expect(fullMapRequest.data.type == .map)
        #expect(fullMapRequest.data.data == nil)
        #expect(sutPlayer.gameModel.gameUpdateType == .table)
        #expect(await rootPlayer.mapRoot.gameController.currentId != mapId)
        #expect(!rootPlayer.photoRoot.gameController.photoGameModel.openPhotoSpace)

        let fullMapPayload = try #require(try await sut.handle(fullMapRequest))
        #expect(fullMapPayload.id == mapId)
        #expect(fullMapPayload.type == .map)
        #expect(fullMapPayload.type != .photo)
        #expect(fullMapPayload.version == version)
        #expect(fullMapPayload.data != nil)

        await sut.send(type: fullMapRequest.type, subtype: fullMapRequest.subType, updated: fullMapPayload)
        let fullMapReveal = try #require(masterStoreAbstractionMock.sendResponseData as? GameNetworkModel)
        #expect(fullMapReveal.type == .reveal)
        #expect(fullMapReveal.subType == .show)
        #expect(fullMapReveal.data.id == mapId)
        #expect(fullMapReveal.data.type == .map)
        #expect(fullMapReveal.data.type != .photo)

        let mapRevealAck = try #require(try await sutPlayer.handle(fullMapReveal))
        #expect(mapRevealAck.subType == .ok)
        #expect(await rootPlayer.mapRoot.gameController.currentId == mapId)
        #expect(sutPlayer.gameModel.gameUpdateType == .map)
        #expect(!rootPlayer.photoRoot.gameController.photoGameModel.openPhotoSpace)
    }
    
    @Test func handlePhoto() async throws {
        try await setUp()
        try await importTestData(into: rootSut)
        try await importPhotoTestData(into: rootSut)
        try #require(rootSut.photoRoot.itemController.itemDataModel.items.count == 30)

        rootSut.adventureRoot.startGame()
        rootPlayer.adventureRoot.startGame()

        // send show audio
        let photoId = rootSut.photoRoot.itemController.itemDataModel.items[0]
        let version = rootSut.photoRoot.itemController.itemOrEmpty(for: photoId).version
        let photoShareData = await rootSut.photoRoot.gameController.share(id: photoId)
        await sut.show(for: photoShareData)
        var sendedShowPhotoData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(nil != sendedShowPhotoData)

        var result = try await sutPlayer.handle(sendedShowPhotoData!)
        #expect(nil != result)
        #expect(result!.subType == .show)
        #expect(await rootPlayer.photoRoot.gameController.currentId != photoId)

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
        #expect(await rootPlayer.photoRoot.gameController.currentId == photoId)
        #expect(rootPlayer.photoRoot.gameController.gameItem(for: photoId).version == version)
    }

    @Test("V2 gamemaster and V1 player exchange dice and photo through controllers")
    func v2MasterAndV1PlayerExchangeDiceAndPhotoThroughControllers() async throws {
        let env = try await LinkedMasterPlayerControllerTestEnvironment.create(
            masterToPlayer: .currentDecodedByV1,
            playerToMaster: .v1Envelope
        )
        try await importTestData(into: env.masterRoot)
        try await importDiceTestData(into: env.masterRoot)
        try await importDiceTestData(into: env.playerRoot)
        env.masterRoot.adventureRoot.startGame()
        env.playerRoot.adventureRoot.startGame()

        await env.master.ready(for: env.connectionId)

        let diceId = env.masterRoot.diceRoot.itemController.itemDataModel.items[0]
        let tableId = env.masterRoot.tableRoot.itemController.itemDataModel.items[0]
        let resultCategory = ResultCategory(id: tableId, module: .table)
        let masterDiceData = await env.masterRoot.diceRoot.gameController.createDiceResult(for: diceId, resultCategory: resultCategory)

        await env.master.game(message: masterDiceData, actionType: .generic)
        #expect(env.playerRoot.diceRoot.gameController.diceGameModel.playerDice.count == 1)
        #expect(env.playerRoot.diceRoot.gameController.diceGameModel.playerDice.first?.name == "Andrenalin")

        let playerDiceId = try #require(env.playerRoot.diceRoot.gameController.gameModel.items.first)
        let playerDiceData = await env.playerRoot.diceRoot.gameController.createDiceResult(for: playerDiceId, resultCategory: resultCategory)

        await env.player.game(message: playerDiceData, actionType: .generic)
        #expect(env.masterRoot.diceRoot.gameController.diceGameModel.playerDice.count == 1)
        #expect(env.masterRoot.diceRoot.gameController.diceGameModel.playerDice.first?.name == "AndrenalinPlayer")

        let photoEnv = try await LinkedMasterPlayerControllerTestEnvironment.create(
            masterToPlayer: .currentDecodedByV1,
            playerToMaster: .v1Envelope
        )
        try await importTestData(into: photoEnv.masterRoot)
        try await importPhotoTestData(into: photoEnv.masterRoot)
        photoEnv.masterRoot.adventureRoot.startGame()
        photoEnv.playerRoot.adventureRoot.startGame()
        await photoEnv.master.ready(for: photoEnv.connectionId)

        let photoId = photoEnv.masterRoot.photoRoot.itemController.itemDataModel.items[0]
        let version = photoEnv.masterRoot.photoRoot.itemController.itemOrEmpty(for: photoId).version
        let photoShareData = await photoEnv.masterRoot.photoRoot.gameController.share(id: photoId)

        await photoEnv.master.show(for: photoShareData)
        #expect(await photoEnv.playerRoot.photoRoot.gameController.currentId == photoId)
        #expect(photoEnv.playerRoot.photoRoot.gameController.gameItem(for: photoId).version == version)
        #expect(await photoEnv.playerRoot.photoRoot.gameController.hasLocalFileData(for: photoId))

        let playerPhotoEnv = try await LinkedMasterPlayerControllerTestEnvironment.create(
            masterToPlayer: .currentDecodedByV1,
            playerToMaster: .v1Envelope
        )
        try await importTestData(into: playerPhotoEnv.playerRoot)
        try await importPhotoTestData(into: playerPhotoEnv.playerRoot)
        playerPhotoEnv.masterRoot.adventureRoot.startGame()
        playerPhotoEnv.playerRoot.adventureRoot.startGame()
        await playerPhotoEnv.master.ready(for: playerPhotoEnv.connectionId)

        let playerPhotoId = playerPhotoEnv.playerRoot.photoRoot.itemController.itemDataModel.items[0]
        let playerPhotoVersion = playerPhotoEnv.playerRoot.photoRoot.itemController.itemOrEmpty(for: playerPhotoId).version
        let playerPhotoData = try await playerPhotoEnv.playerRoot.photoRoot.gameController.createGameData(for: playerPhotoId)

        await playerPhotoEnv.player.game(message: playerPhotoData, actionType: .generic)
        #expect(playerPhotoEnv.masterRoot.photoRoot.gameController.gameModel.items.contains(playerPhotoId))
        #expect(playerPhotoEnv.masterRoot.photoRoot.gameController.gameItem(for: playerPhotoId).version == playerPhotoVersion)
        #expect(await playerPhotoEnv.masterRoot.photoRoot.gameController.hasLocalFileData(for: playerPhotoId))
    }

    @Test("V1 gamemaster and V2 player exchange dice and photo through controllers")
    func v1MasterAndV2PlayerExchangeDiceAndPhotoThroughControllers() async throws {
        let env = try await LinkedMasterPlayerControllerTestEnvironment.create(
            masterToPlayer: .v1Envelope,
            playerToMaster: .currentDecodedByV1
        )
        try await importTestData(into: env.masterRoot)
        try await importDiceTestData(into: env.masterRoot)
        try await importDiceTestData(into: env.playerRoot)
        env.masterRoot.adventureRoot.startGame()
        env.playerRoot.adventureRoot.startGame()

        await env.master.ready(for: env.connectionId)

        let diceId = env.masterRoot.diceRoot.itemController.itemDataModel.items[0]
        let tableId = env.masterRoot.tableRoot.itemController.itemDataModel.items[0]
        let resultCategory = ResultCategory(id: tableId, module: .table)
        let masterDiceData = await env.masterRoot.diceRoot.gameController.createDiceResult(for: diceId, resultCategory: resultCategory)

        await env.master.game(message: masterDiceData, actionType: .generic)
        #expect(env.playerRoot.diceRoot.gameController.diceGameModel.playerDice.count == 1)
        #expect(env.playerRoot.diceRoot.gameController.diceGameModel.playerDice.first?.name == "Andrenalin")

        let playerDiceId = try #require(env.playerRoot.diceRoot.gameController.gameModel.items.first)
        let playerDiceData = await env.playerRoot.diceRoot.gameController.createDiceResult(for: playerDiceId, resultCategory: resultCategory)

        await env.player.game(message: playerDiceData, actionType: .generic)
        #expect(env.masterRoot.diceRoot.gameController.diceGameModel.playerDice.count == 1)
        #expect(env.masterRoot.diceRoot.gameController.diceGameModel.playerDice.first?.name == "AndrenalinPlayer")

        let photoEnv = try await LinkedMasterPlayerControllerTestEnvironment.create(
            masterToPlayer: .v1Envelope,
            playerToMaster: .currentDecodedByV1
        )
        try await importTestData(into: photoEnv.masterRoot)
        try await importPhotoTestData(into: photoEnv.masterRoot)
        photoEnv.masterRoot.adventureRoot.startGame()
        photoEnv.playerRoot.adventureRoot.startGame()
        await photoEnv.master.ready(for: photoEnv.connectionId)

        let photoId = photoEnv.masterRoot.photoRoot.itemController.itemDataModel.items[0]
        let version = photoEnv.masterRoot.photoRoot.itemController.itemOrEmpty(for: photoId).version
        let photoShareData = await photoEnv.masterRoot.photoRoot.gameController.share(id: photoId)

        await photoEnv.master.show(for: photoShareData)
        #expect(await photoEnv.playerRoot.photoRoot.gameController.currentId == photoId)
        #expect(photoEnv.playerRoot.photoRoot.gameController.gameItem(for: photoId).version == version)
        #expect(await photoEnv.playerRoot.photoRoot.gameController.hasLocalFileData(for: photoId))

        let playerPhotoEnv = try await LinkedMasterPlayerControllerTestEnvironment.create(
            masterToPlayer: .v1Envelope,
            playerToMaster: .currentDecodedByV1
        )
        try await importTestData(into: playerPhotoEnv.playerRoot)
        try await importPhotoTestData(into: playerPhotoEnv.playerRoot)
        playerPhotoEnv.masterRoot.adventureRoot.startGame()
        playerPhotoEnv.playerRoot.adventureRoot.startGame()
        await playerPhotoEnv.master.ready(for: playerPhotoEnv.connectionId)

        let playerPhotoId = playerPhotoEnv.playerRoot.photoRoot.itemController.itemDataModel.items[0]
        let playerPhotoVersion = playerPhotoEnv.playerRoot.photoRoot.itemController.itemOrEmpty(for: playerPhotoId).version
        let playerPhotoData = try await playerPhotoEnv.playerRoot.photoRoot.gameController.createGameData(for: playerPhotoId)

        await playerPhotoEnv.player.game(message: playerPhotoData, actionType: .generic)
        #expect(playerPhotoEnv.masterRoot.photoRoot.gameController.gameModel.items.contains(playerPhotoId))
        #expect(playerPhotoEnv.masterRoot.photoRoot.gameController.gameItem(for: playerPhotoId).version == playerPhotoVersion)
        #expect(await playerPhotoEnv.masterRoot.photoRoot.gameController.hasLocalFileData(for: playerPhotoId))
    }

    @Test func handleSapce() async throws {
        try await setUp()
        try await importTestData(into: rootSut)
        try await importSpaceTestData(into: rootSut)
        try #require(rootSut.spaceRoot.itemController.itemDataModel.items.count == 1)

        rootSut.adventureRoot.startGame()
        rootPlayer.adventureRoot.startGame()

        // send show space
        let spaceId = rootSut.spaceRoot.itemController.itemDataModel.items[0]
        let version = rootSut.spaceRoot.itemController.itemOrEmpty(for: spaceId).version
        let spaceShareData = await rootSut.spaceRoot.gameController.share(id: spaceId)
        await sut.show(for: spaceShareData)
        var sendedShowSpaceData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(nil != sendedShowSpaceData)

        var result = try await sutPlayer.handle(sendedShowSpaceData!)
        #expect(nil != result)
        #expect(result!.subType == .show)
        #expect(await rootPlayer.spaceRoot.gameController.currentId != spaceId)

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
        #expect(await rootPlayer.spaceRoot.gameController.currentId == spaceId)
        #expect(rootPlayer.spaceRoot.gameController.gameItem(for: spaceId).version == version)
    }

    @Test func handleTable() async throws {
        try await setUp()
        try await importTestData(into: rootSut)
        try await importTableTestData(into: rootSut)
        try #require(rootSut.tableRoot.itemController.itemDataModel.items.count == 69)

        rootSut.adventureRoot.startGame()
        rootPlayer.adventureRoot.startGame()

        // send show table
        let tableId = rootSut.tableRoot.itemController.itemDataModel.items[0]
        let version = rootSut.tableRoot.itemController.itemOrEmpty(for: tableId).version
        let tableShareData = await rootSut.tableRoot.gameController.share(id: tableId)
        await sut.show(for: tableShareData)
        var sendedShowTableData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(nil != sendedShowTableData)

        var result = try await sutPlayer.handle(sendedShowTableData!)
        #expect(nil != result)
        #expect(result!.subType == .show)
        #expect(await rootPlayer.tableRoot.gameController.currentId != tableId)

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
        #expect(await rootPlayer.tableRoot.gameController.currentId == tableId)
        #expect(rootPlayer.tableRoot.gameController.gameItem(for: tableId).version == version)
    }
}

private enum CompatibilityWireMode: Sendable {
    case current
    case v1Envelope
    case currentDecodedByV1
}

@MainActor
private struct LinkedMasterPlayerControllerTestEnvironment {
    let link: InMemoryLocalNetworkLink
    let master: MasterController
    let masterRoot: GameRoot
    let masterGameConfig: GameConfigModel
    let player: PlayerController
    let playerRoot: GameRoot
    let playerGameConfig: GameConfigModel
    let connectionId: ConnectionController.ID

    static func create(
        masterToPlayer: CompatibilityWireMode,
        playerToMaster: CompatibilityWireMode
    ) async throws -> LinkedMasterPlayerControllerTestEnvironment {
        let link = InMemoryLocalNetworkLink(masterToPlayer: masterToPlayer, playerToMaster: playerToMaster)

        let masterNetwork = GameNetworkController(
            name: "Master Link",
            proxy: false,
            masterBuilder: { _, _ in link.masterStore },
            playerBuilder: { _, _ in link.unusedPlayerStore }
        )
        let playerNetwork = GameNetworkController(
            name: "Player Link",
            proxy: false,
            masterBuilder: { _, _ in link.unusedMasterStore },
            playerBuilder: { _, _ in link.playerStore }
        )
        link.masterNetwork = masterNetwork
        link.playerNetwork = playerNetwork

        let masterProxyNetwork = GameNetworkController(
            name: "Master Proxy Link",
            proxy: true,
            masterBuilder: { _, _ in MasterNetworkControllableMock() },
            playerBuilder: { _, _ in PlayerStoreAbstractionMock() }
        )
        let playerProxyNetwork = GameNetworkController(
            name: "Player Proxy Link",
            proxy: true,
            masterBuilder: { _, _ in MasterNetworkControllableMock() },
            playerBuilder: { _, _ in PlayerStoreAbstractionMock() }
        )

        let masterRoot = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: masterRoot.adventureRoot)
        try await MockRoot.resetGameController(for: masterRoot)
        masterRoot.networkStore = masterNetwork
        masterRoot.networkProxyStore = masterProxyNetwork

        let masterId = UUID()
        let masterConfig = GameConfigModel(
            id: masterId,
            state: .started,
            master: MasterGameModel(id: masterId, type: .master, name: "Andrenalin")
        )
        masterRoot.gameModel.reset(gameConfig: masterConfig)
        let master = MasterController(root: masterRoot, asProxy: false)

        let playerRoot = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: playerRoot.adventureRoot)
        try await MockRoot.resetGameController(for: playerRoot)
        playerRoot.networkStore = playerNetwork
        playerRoot.networkProxyStore = playerProxyNetwork

        let playerId = UUID()
        let playerConfig = GameConfigModel(id: playerId, state: .started, master: .empty)
        let playerRoster = GameRosterModel(players: [
            PlayerGameModel(id: playerId, type: .player, name: "AndrenalinPlayer")
        ])
        playerRoot.gameModel.reset(gameConfig: playerConfig, gameRoster: playerRoster)
        let player = PlayerController(root: playerRoot, asGameMaster: false)

        return LinkedMasterPlayerControllerTestEnvironment(
            link: link,
            master: master,
            masterRoot: masterRoot,
            masterGameConfig: masterConfig,
            player: player,
            playerRoot: playerRoot,
            playerGameConfig: playerConfig,
            connectionId: link.connectionId
        )
    }
}

private final class InMemoryLocalNetworkLink: @unchecked Sendable {
    let connectionId = ConnectionController.ID()
    let masterToPlayer: CompatibilityWireMode
    let playerToMaster: CompatibilityWireMode
    let masterStore: InMemoryMasterNetworkStore
    let playerStore: InMemoryPlayerNetworkStore
    let unusedMasterStore: MasterNetworkControllableMock
    let unusedPlayerStore: PlayerStoreAbstractionMock
    weak var masterNetwork: GameNetworkController?
    weak var playerNetwork: GameNetworkController?

    @MainActor
    init(masterToPlayer: CompatibilityWireMode, playerToMaster: CompatibilityWireMode) {
        self.masterToPlayer = masterToPlayer
        self.playerToMaster = playerToMaster
        masterStore = InMemoryMasterNetworkStore()
        playerStore = InMemoryPlayerNetworkStore()
        unusedMasterStore = MasterNetworkControllableMock()
        unusedPlayerStore = PlayerStoreAbstractionMock()
        masterStore.link = self
        playerStore.link = self
    }

    func relayMasterToPlayer(_ content: MessageMapper?) async {
        await playerNetwork?.playerReceived(data: encodedData(for: content, mode: masterToPlayer))
    }

    func relayPlayerToMaster(_ content: MessageMapper?) async {
        await masterNetwork?.masterReceived(data: encodedData(for: content, mode: playerToMaster), for: connectionId, fileJournal: false)
    }

    private func encodedData(for content: MessageMapper?, mode: CompatibilityWireMode) -> Data? {
        guard let model = content as? GameNetworkModel else {
            return content?.encodeData()
        }

        switch mode {
        case .current:
            return model.encodeData()
        case .v1Envelope:
            return try? JSONEncoder().encode(model.v1Model)
        case .currentDecodedByV1:
            guard let data = model.encodeData(),
                  let v1Envelope = try? JSONDecoder().decode(GameNetworkModelV1.self, from: data)
            else {
                return nil
            }
            return try? JSONEncoder().encode(v1Envelope)
        }
    }
}

private final class InMemoryMasterNetworkStore: MasterNetworkControllable, @unchecked Sendable {
    @MainActor let networkModel: MasterNetworkNodel
    weak var link: InMemoryLocalNetworkLink?

    @MainActor
    init(networkModel: MasterNetworkNodel = MasterNetworkNodel(name: "Linked Master")) {
        self.networkModel = networkModel
    }

    @MainActor func startStreaming() {}
    @MainActor func stopStreaming() {}
    @MainActor func toggleStreaming() {}
    @MainActor func startProxyStreaming() {}

    func sendResponse(data: MessageMapper?, id: ConnectionController.ID) async {
        guard id == link?.connectionId else { return }
        await link?.relayMasterToPlayer(data)
    }

    func sendResponse(data: MessageMapper?) async {
        await link?.relayMasterToPlayer(data)
    }

    func sendResponse(data: MessageMapper?, except: ConnectionController.ID) async {
        guard except != link?.connectionId else { return }
        await link?.relayMasterToPlayer(data)
    }
}

private final class InMemoryPlayerNetworkStore: PlayerNetworkControllable, @unchecked Sendable {
    @MainActor let networkModel = PlayerNetworkNodel(name: "Linked Player")
    let browserManager: BrowserManager
    weak var link: InMemoryLocalNetworkLink?

    @MainActor
    init(browserManager: BrowserManager = BrowserManager()) {
        self.browserManager = browserManager
    }

    @MainActor func toggleConnection(to _: BrowserGameModel) async {}
    @MainActor func stop() async {}

    func request(with content: MessageMapper?) async {
        await link?.relayPlayerToMaster(content)
    }
}

private extension MasterPlayerControllerTests {
    func importTestData(into root: GameRoot) async throws {
        let bundle = ResourcesDebug.bundle
        let url = bundle.url(forResource: ResourcesDebug.adventureTestData, withExtension: "gmz").unsafelyUnwrapped
        let task = root.adventureRoot.importControllable.importUrl(from: url)
        let _ = try await task.value
    }
    
    func importDiceTestData(into root: GameRoot) async throws {
        let bundle = ResourcesDebug.bundle
        let url = bundle.url(forResource: ResourcesDebug.diceTestData, withExtension: "gmz").unsafelyUnwrapped
        let task = root.adventureRoot.importControllable.importUrl(from: url)
        let _ = try await task.value
    }
    
    func importPhotoTestData(into root: GameRoot) async throws {
        let bundle = ResourcesDebug.bundle
        let url = bundle.url(forResource: ResourcesDebug.photoTestData, withExtension: "gmz").unsafelyUnwrapped
        let task = root.adventureRoot.importControllable.importUrl(from: url)
        let _ = try await task.value
    }

    func importSpaceTestData(into root: GameRoot) async throws {
        let bundle = ResourcesDebug.bundle
        let url = bundle.url(forResource: ResourcesDebug.spaceTestData, withExtension: "gmz").unsafelyUnwrapped
        let task = root.adventureRoot.importControllable.importUrl(from: url)
        let _ = try await task.value
    }

    func importTableTestData(into root: GameRoot) async throws {
        let bundle = ResourcesDebug.bundle
        let url = bundle.url(forResource: ResourcesDebug.tableTestData, withExtension: "gmz").unsafelyUnwrapped
        let task = root.adventureRoot.importControllable.importUrl(from: url)
        let _ = try await task.value
    }

}

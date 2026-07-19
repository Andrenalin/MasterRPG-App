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

@Suite(.serialized)
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
        #expect(rootSut.audioRoot.gameController.gameModel.playerReport(for: audioId) == [gameConfigModelPlayer.id])
        #expect(rootSut.audioRoot.gameController.gameModel.playerReport(for: subAudioId) == [gameConfigModelPlayer.id])

        let playData = rootSut.audioRoot.gameController.requestPlay(id: audioId)
        rootPlayer.audioRoot.gameController.gameModel.setCurrent(players: [
            gameConfigModelPlayer.id,
            gameConfigModelSut.id
        ])
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
        let expectedPlayers = Set([gameConfigModelPlayer.id, gameConfigModelSut.id])
        #expect(Set(rootPlayer.audioRoot.gameController.gameModel.playerReport(for: audioId)) == expectedPlayers)
        #expect(Set(rootPlayer.audioRoot.gameController.gameModel.playerReport(for: subAudioId)) == expectedPlayers)
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

        // send show map — the first show of this version ships the whole package
        let mapId = rootSut.mapRoot.itemController.itemDataModel.items[0]
        let photoId = rootSut.mapRoot.itemController.itemOrEmpty(for: mapId).photoId
        #expect(nil != photoId)
        let mapShareData = await rootSut.mapRoot.gameController.shareMap(id: mapId)
        await sut.show(for: mapShareData)
        let sendedShowMapData = try #require(masterStoreAbstractionMock.sendResponseData as? GameNetworkModel)
        #expect(sendedShowMapData.data.data != nil)
        #expect(sendedShowMapData.usesFileJournal)
        #expect(RPGSharePlayController.usesJournalTransport(
            for: sendedShowMapData,
            fileJournal: sendedShowMapData.usesFileJournal,
            journalAvailable: true
        ))

        var result = try await sutPlayer.handle(sendedShowMapData)
        #expect(nil != result)
        #expect(result!.subType == .ok)
        #expect(await rootPlayer.mapRoot.gameController.currentId == mapId)
        let playerPhoto1 = rootPlayer.photoRoot.gameController.gameItem(for: photoId!).version
        let sutPhoto1 = rootSut.photoRoot.gameController.gameItem(for: photoId!).version
        #expect(playerPhoto1 == sutPhoto1)

        // a reshow announces the map only by reference
        await sut.show(for: mapShareData)
        let reshowReference = try #require(masterStoreAbstractionMock.sendResponseData as? GameNetworkModel)
        #expect(reshowReference.data.id == mapId)
        #expect(reshowReference.data.data == nil)
        #expect(!reshowReference.usesFileJournal)
        result = try await sutPlayer.handle(reshowReference)
        #expect(result?.subType == .ok)

        let entry = rootSut.mapRoot.gameController.gameItem(for: mapId).entries[0]
        #expect(!entry.isShown)
        rootSut.mapRoot.gameController.gameItem(for: mapId).toggle(entry.id)
        let existingPinPhotoId = try #require(photoId)
        let existingPhotoPin = MapPinModel(
            id: UUID(),
            name: "Known Character",
            photoId: existingPinPhotoId
        )
        let missingPinPhotoId = UUID()
        let missingPhotoPin = MapPinModel(
            id: UUID(),
            name: "New Monster",
            photoId: missingPinPhotoId
        )
        rootSut.mapRoot.gameController.gameItem(for: mapId).mapPins.append(contentsOf: [existingPhotoPin, missingPhotoPin])
        playerStoreAbstractionMock.requestData = nil
        playerStoreAbstractionMock.requestHistory = []
        #expect(rootSut.mapRoot.gameController.gameItem(for: mapId)[entry.id].isShown)
        await sut.game(message: rootSut.mapRoot.gameController.networkMapUpdate(for: mapId), actionType: .mapState)
        let updatedMapData = try #require(masterStoreAbstractionMock.sendResponseData as? GameNetworkModel)
        #expect(!rootPlayer.mapRoot.gameController.gameItem(for: mapId).entries[0].isShown)
        
        result = try await sutPlayer.handle(updatedMapData)
        let contentRequest = try #require(result)
        #expect(contentRequest.type == .update)
        #expect(contentRequest.subType == .generic)
        #expect(contentRequest.data.id == mapId)
        #expect(contentRequest.data.data == nil)
        #expect(contentRequest.data.assetVersion == updatedMapData.data.assetVersion)
        #expect(contentRequest.data.contentVersion == updatedMapData.data.contentVersion)

        // Structural Map metadata is repaired separately from its live state.
        // Applying it also releases the queued mapState in generation order.
        let contentUpdate = rootSut.gameModel.outgoingMessage(
            counter: updatedMapData.counter + 1,
            type: .update,
            subType: .generic,
            asMaster: true,
            data: await rootSut.mapRoot.mapGameControllable.networkMapContentUpdate(for: mapId)
        )
        result = try await sutPlayer.handle(contentUpdate)
        #expect(result == nil)
        let mapPlayer = rootPlayer.mapRoot.gameController.gameItem(for: mapId)
        let mapMaster = rootSut.mapRoot.gameController.gameItem(for: mapId)
        #expect(mapPlayer.entries[0].isShown)
        #expect(mapPlayer.entries == mapMaster.entries)
        #expect(mapPlayer.mapPins.contains { $0.id == existingPhotoPin.id && $0.photoId == existingPinPhotoId })
        #expect(mapPlayer.mapPins.contains { $0.id == missingPhotoPin.id && $0.photoId == missingPinPhotoId })

        // mapState carries both pin references. The player already owns one
        // photo and must issue exactly one data-less request for the absent id.
        let repairRequests = playerStoreAbstractionMock.requestHistory.compactMap { $0 as? GameNetworkModel }
        #expect(repairRequests.count == 1)
        let repairRequest = try #require(repairRequests.first)
        #expect(repairRequest.type == .store)
        #expect(repairRequest.subType == .store)
        #expect(repairRequest.data.type == .photo)
        #expect(repairRequest.data.id == missingPinPhotoId)
        #expect(repairRequest.data.data == nil)
        let usesFileJournal = PlayerController.usesFileJournal(for: repairRequest)
        #expect(!usesFileJournal)
        #expect(!RPGSharePlayController.usesJournalTransport(
            for: repairRequest,
            fileJournal: usesFileJournal,
            journalAvailable: true
        ))
    }

    @Test func delayedFullMapAppliesMapStateThatArrivedFirst() async throws {
        try await setUp()
        try await importTestData(into: rootSut)
        rootSut.adventureRoot.startGame()
        rootPlayer.adventureRoot.startGame()

        let mapId = try #require(rootSut.mapRoot.itemController.itemDataModel.items.first)
        await sut.show(for: rootSut.mapRoot.gameController.shareMap(id: mapId))
        let delayedFullMap = try #require(masterStoreAbstractionMock.sendResponseData as? GameNetworkModel)
        #expect(delayedFullMap.data.data != nil)

        let masterMap = rootSut.mapRoot.gameController.gameItem(for: mapId)
        let entryId = try #require(masterMap.entries.first?.id)
        let originalVisibility = masterMap[entryId].isShown
        masterMap.toggle(entryId)
        let updatedVisibility = masterMap[entryId].isShown
        #expect(updatedVisibility != originalVisibility)

        await sut.game(
            message: rootSut.mapRoot.gameController.networkMapUpdate(for: mapId),
            actionType: .mapState
        )
        let earlyMapState = try #require(masterStoreAbstractionMock.sendResponseData as? GameNetworkModel)
        let recoveryRequest = try #require(try await sutPlayer.handle(earlyMapState))
        #expect(recoveryRequest.type == .reveal)
        #expect(recoveryRequest.subType == .mapState)
        #expect(recoveryRequest.data.version == earlyMapState.data.version)
        #expect(await !rootPlayer.mapRoot.gameControllable.hasItem(id: mapId, version: 0))

        let acknowledgement = try #require(try await sutPlayer.handle(delayedFullMap))
        #expect(acknowledgement.subType == .ok)

        let playerMap = rootPlayer.mapRoot.gameController.gameItem(for: mapId)
        let playerEntry = try #require(playerMap.entries.first(where: { $0.id == entryId }))
        #expect(playerEntry.isShown == updatedVisibility)
        #expect(playerEntry.isShown != originalVisibility)
        #expect(sutPlayer.gameModel.gameUpdateType == .map)
        #expect(!sutPlayer.gameModel.pendingMapRequests.contains(mapId))
    }

    @Test func localPlayerMapRecoveryStillReceivesFullMapImmediately() async throws {
        try await setUp()
        try await importTestData(into: rootSut)
        rootSut.adventureRoot.startGame()
        rootPlayer.adventureRoot.startGame()

        let mapId = try #require(rootSut.mapRoot.itemController.itemDataModel.items.first)
        let mapReference = await rootSut.mapRoot.gameController.shareMap(id: mapId)
        await sut.show(for: mapReference)
        masterStoreAbstractionMock.sendResponseHistory = []

        // This is a post-join recovery request. Model the authority established
        // by the first master packet so sender/session validation exercises the
        // same path as a connected local player.
        rootPlayer.gameModel.reset(
            gameConfig: GameConfigModel(
                id: gameConfigModelPlayer.id,
                state: .started,
                master: gameConfigModelSut.master
            ),
            gameRoster: GameRosterModel(players: [
                PlayerGameModel(
                    id: gameConfigModelPlayer.id,
                    type: .player,
                    name: "AndrenalinPlayer"
                )
            ])
        )

        let request = rootPlayer.gameModel.outgoingMessage(
            counter: 50,
            type: .reveal,
            subType: .mapState,
            asMaster: false,
            purpose: .assetRequest,
            data: NetworkCodableDataType(
                id: mapId,
                type: .map,
                version: mapReference.version,
                data: nil,
                assetVersion: mapReference.assetVersion,
                contentVersion: mapReference.contentVersion
            )
        )

        await sut.receivedProcess(request, connectionId: UUID())

        let responses = masterStoreAbstractionMock.sendResponseHistory.compactMap { $0 as? GameNetworkModel }
        let fullMap = responses.first {
            $0.type == .reveal &&
                $0.subType == .store &&
                $0.data.id == mapId &&
                $0.data.data != nil
        }
        #expect(fullMap != nil)
        #expect(fullMap?.targetId == gameConfigModelPlayer.id)
    }

    @Test func changedMapContentUsesPhotoFreeUpdateWithoutRepublishingSharePlayJournal() async throws {
        try await setUp()
        try await importTestData(into: rootSut)
        rootSut.adventureRoot.startGame()
        rootPlayer.adventureRoot.startGame()

        let mapId = try #require(rootSut.mapRoot.itemController.itemDataModel.items.first)
        let firstReference = await rootSut.mapRoot.gameController.shareMap(id: mapId)
        let firstAssetVersion = try #require(firstReference.assetVersion)
        let firstContentVersion = try #require(firstReference.contentVersion)

        await sut.show(for: firstReference)
        let firstFullMap = try #require(masterStoreAbstractionMock.sendResponseData as? GameNetworkModel)
        let fullMapBytes = try #require(firstFullMap.data.data)
        #expect(firstFullMap.targetId == nil)
        #expect(firstFullMap.data.assetVersion == firstAssetVersion)
        #expect(firstFullMap.data.contentVersion == firstContentVersion)
        #expect(RPGSharePlayController.usesJournalTransport(
            for: firstFullMap,
            fileJournal: firstFullMap.usesFileJournal,
            journalAvailable: true
        ))
        _ = try #require(try await sutPlayer.handle(firstFullMap))

        let masterMap = rootSut.mapRoot.gameController.gameItem(for: mapId)
        masterMap.pinScale += 0.5
        masterMap.hexMapScale += 0.25

        // Scale edits change only the photo-free content fingerprint. The
        // background asset still identifies the same Journal attachment.
        let changedReference = await rootSut.mapRoot.gameController.shareMap(id: mapId)
        let changedContentVersion = try #require(changedReference.contentVersion)
        #expect(changedReference.assetVersion == firstAssetVersion)
        #expect(changedContentVersion != firstContentVersion)

        let contentUpdate = await rootSut.mapRoot.gameController.networkMapContentUpdate(for: mapId)
        let updateBytes = try #require(contentUpdate.data)
        let updateJSON = try #require(String(data: updateBytes, encoding: .utf8))
        let decodedUpdate = try JSONDecoder().decode(MapUpdatePayload.self, from: updateBytes)
        #expect(contentUpdate.assetVersion == firstAssetVersion)
        #expect(contentUpdate.contentVersion == changedContentVersion)
        #expect(decodedUpdate.schemaVersion == 1)
        #expect(decodedUpdate.contentVersion == changedContentVersion)
        #expect(updateBytes.count < fullMapBytes.count / 10)
        #expect(updateBytes.first == Character("{").asciiValue)
        #expect(!updateJSON.contains("\"fileUrl\""))
        #expect(!updateJSON.contains("\"contentHash\""))

        playerStoreAbstractionMock.requestData = nil
        playerStoreAbstractionMock.requestHistory = []
        await sut.game(message: contentUpdate, actionType: .generic)
        let sentUpdate = try #require(masterStoreAbstractionMock.sendResponseData as? GameNetworkModel)
        #expect(sentUpdate.counter > firstFullMap.counter)
        #expect(sentUpdate.type == .update)
        #expect(sentUpdate.subType == .generic)
        #expect(sentUpdate.data.id == mapId)
        #expect(sentUpdate.data.assetVersion == firstAssetVersion)
        #expect(sentUpdate.data.contentVersion == changedContentVersion)
        #expect(sentUpdate.data.data == updateBytes)
        #expect(!sentUpdate.usesFileJournal)
        #expect(!RPGSharePlayController.usesJournalTransport(
            for: sentUpdate,
            fileJournal: sentUpdate.usesFileJournal,
            journalAvailable: true
        ))

        let response = try await sutPlayer.handle(sentUpdate)
        #expect(response == nil)
        let playerMap = rootPlayer.mapRoot.gameController.gameItem(for: mapId)
        #expect(playerMap.pinScale == masterMap.pinScale)
        #expect(playerMap.hexMapScale == masterMap.hexMapScale)
        #expect(playerStoreAbstractionMock.requestData == nil)
        #expect(playerStoreAbstractionMock.requestHistory.isEmpty)

        // The original Journal attachment may finish after the messenger update.
        // It must still reveal the map, but must not roll its old scales back.
        _ = try await sutPlayer.handleMap(firstFullMap)
        #expect(playerMap.pinScale == masterMap.pinScale)
        #expect(playerMap.hexMapScale == masterMap.hexMapScale)
    }

    @Test func mapRevealUsesAssetFingerprintInsteadOfLegacyScaleVersion() async throws {
        try await setUp()
        try await importTestData(into: rootSut)
        rootSut.adventureRoot.startGame()
        rootPlayer.adventureRoot.startGame()

        let mapId = try #require(rootSut.mapRoot.itemController.itemDataModel.items.first)
        await sut.show(for: rootSut.mapRoot.gameController.shareMap(id: mapId))
        let initialFullMap = try #require(masterStoreAbstractionMock.sendResponseData as? GameNetworkModel)
        _ = try #require(try await sutPlayer.handleMap(initialFullMap))

        let localAssetVersion = await rootPlayer.mapRoot.gameController.mapAssetVersion(for: mapId)
        #expect(localAssetVersion == initialFullMap.data.assetVersion)

        // A matching reference reuses the local map without requesting bytes.
        var matchingReference = initialFullMap
        matchingReference.counter += 1
        matchingReference.data = NetworkCodableDataType(
            id: mapId,
            type: .map,
            version: initialFullMap.data.version,
            assetVersion: localAssetVersion,
            contentVersion: initialFullMap.data.contentVersion
        )
        let matchingResponse = try #require(try await sutPlayer.handleMap(matchingReference))
        #expect(matchingResponse.subType == .ok)

        // Matching background/scales do not imply matching structural content.
        // A newly sequenced current-protocol full payload must still be imported.
        let matchingAssetReplacementName = "Matching asset, newer map"
        let masterMap = rootSut.mapRoot.gameController.gameItem(for: mapId)
        masterMap.name = matchingAssetReplacementName
        let matchingAssetBase = try await rootSut.mapRoot.gameController.createMapGameData(for: mapId)
        var matchingAssetFull = initialFullMap
        matchingAssetFull.counter = matchingReference.counter + 1
        matchingAssetFull.data = matchingAssetBase
        _ = try #require(try await sutPlayer.handleMap(matchingAssetFull))
        #expect(rootPlayer.mapRoot.gameController.gameItem(for: mapId).name == matchingAssetReplacementName)

        // The same legacy scale version with a different background fingerprint
        // is not reusable: a metadata-only reveal must request the full package.
        // Change the real background generation so the eventual package and its
        // advertised asset fingerprint remain an internally consistent pair.
        let backgroundPhotoId = try #require(masterMap.photoId)
        let backgroundPhoto = rootSut.photoRoot.gameController.gameItem(for: backgroundPhotoId)
        var replacementFile = try #require(backgroundPhoto.fileUrl)
        let replacementImage = try #require(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
        replacementFile.resetData(replacementImage)
        backgroundPhoto.fileUrl = replacementFile
        let replacementName = "Replacement background map"
        masterMap.name = replacementName
        let replacementBase = try await rootSut.mapRoot.mapGameControllable.createMapGameData(
            for: mapId
        )
        let changedAssetVersion = try #require(replacementBase.assetVersion)
        #expect(changedAssetVersion != localAssetVersion)
        #expect(replacementBase.version == initialFullMap.data.version)
        var mismatchingReference = matchingReference
        mismatchingReference.counter = matchingAssetFull.counter + 1
        mismatchingReference.data = NetworkCodableDataType(
            id: mapId,
            type: .map,
            version: initialFullMap.data.version,
            assetVersion: changedAssetVersion,
            contentVersion: replacementBase.contentVersion
        )
        let request = try #require(try await sutPlayer.handleMap(mismatchingReference))
        #expect(request.subType == .show)
        #expect(request.data.data == nil)

        // When those replacement bytes arrive, import them even though the
        // scale-derived legacy version is unchanged.
        var replacementFull = initialFullMap
        replacementFull.counter = mismatchingReference.counter + 1
        replacementFull.data = replacementBase
        let replacementResponse = try #require(try await sutPlayer.handleMap(replacementFull))
        #expect(replacementResponse.subType == .ok)
        #expect(rootPlayer.mapRoot.gameController.gameItem(for: mapId).name == replacementName)
    }

    @Test func consecutiveSharePlayMapFilesReplaceThePlayerPresentation() async throws {
        try await setUp()
        try await importTestData(into: rootSut)
        try #require(rootSut.mapRoot.itemController.itemDataModel.items.count >= 2)

        rootSut.adventureRoot.startGame()
        rootPlayer.adventureRoot.startGame()

        let mapA = rootSut.mapRoot.itemController.itemDataModel.items[0]
        let mapB = rootSut.mapRoot.itemController.itemDataModel.items[1]

        await sut.show(for: rootSut.mapRoot.gameController.share(id: mapA))
        let showA = try #require(masterStoreAbstractionMock.sendResponseData as? GameNetworkModel)
        #expect(showA.data.data != nil)

        await sut.show(for: rootSut.mapRoot.gameController.share(id: mapB))
        let showB = try #require(masterStoreAbstractionMock.sendResponseData as? GameNetworkModel)
        #expect(showB.data.data != nil)

        // Exercise the same awaited delegate route used by journal attachment
        // delivery, not PlayerController.handle directly.
        networkMock.model.setPlayerDelegate(sutPlayer)
        await networkMock.handleFileUpdate(showA)
        #expect(await rootPlayer.mapRoot.gameController.currentId == mapA)

        await networkMock.handleFileUpdate(showB)
        #expect(await rootPlayer.mapRoot.gameController.currentId == mapB)
        #expect(sutPlayer.gameModel.gameUpdateType == .map)
    }

    @Test func failedJournalStoresRequestBytesForEveryFileBackedModule() async throws {
        try await setUp()
        networkMock.model.setPlayerDelegate(sutPlayer)
        let modules: [NetworkModules] = [.map, .photo, .pdf, .space, .audio]

        for (index, module) in modules.enumerated() {
            let itemId = UUID()
            let version = index + 10
            let metadata = rootSut.gameModel.outgoingMessage(
                counter: index + 60,
                type: .store,
                subType: .store,
                asMaster: true,
                data: NetworkCodableDataType(
                    id: itemId,
                    type: module,
                    version: version,
                    data: nil
                )
            )
            playerStoreAbstractionMock.requestData = nil
            let requestCount = playerStoreAbstractionMock.calledRequest

            await networkMock.handleFileLoadFailure(metadata)

            #expect(playerStoreAbstractionMock.calledRequest == requestCount + 1)
            let request = try #require(playerStoreAbstractionMock.requestData as? GameNetworkModel)
            #expect(request.counter == metadata.counter)
            #expect(request.type == .store)
            #expect(request.subType == .store)
            #expect(request.data.id == itemId)
            #expect(request.data.type == module)
            #expect(request.data.version == version)
            #expect(request.data.data == nil)
            #expect(!request.sender.isMaster)
        }
    }

    @Test func newerMapReferenceRejectsAnOlderDelayedJournalMap() async throws {
        try await setUp()
        try await importTestData(into: rootSut)
        try #require(rootSut.mapRoot.itemController.itemDataModel.items.count >= 2)

        rootSut.adventureRoot.startGame()
        rootPlayer.adventureRoot.startGame()

        let mapA = rootSut.mapRoot.itemController.itemDataModel.items[0]
        let mapB = rootSut.mapRoot.itemController.itemDataModel.items[1]

        await sut.show(for: rootSut.mapRoot.gameController.share(id: mapA))
        var initialMapA = try #require(masterStoreAbstractionMock.sendResponseData as? GameNetworkModel)
        initialMapA.counter = 41

        await sut.show(for: rootSut.mapRoot.gameController.share(id: mapB))
        var delayedMapB = try #require(masterStoreAbstractionMock.sendResponseData as? GameNetworkModel)
        delayedMapB.counter = 42

        var reshowMapA = initialMapA
        reshowMapA.counter = 43
        reshowMapA.data = NetworkCodableDataType(
            id: initialMapA.data.id,
            type: initialMapA.data.type,
            version: initialMapA.data.version,
            data: nil
        )

        networkMock.model.setPlayerDelegate(sutPlayer)
        await networkMock.handleFileUpdate(initialMapA)
        #expect(await rootPlayer.mapRoot.gameController.currentId == mapA)

        // The messenger reference is the newest master intent. Map B's older
        // journal payload finishes afterward and must not restore map B.
        await networkMock.handleUpdate(reshowMapA, id: UUID())
        #expect(await rootPlayer.mapRoot.gameController.currentId == mapA)
        await networkMock.handleFileUpdate(delayedMapB)

        #expect(await rootPlayer.mapRoot.gameController.currentId == mapA)
        #expect(sutPlayer.gameModel.gameUpdateType == .map)

        // mapState recovery uses a fresh counter and `.reveal/.store`, but it
        // repairs an earlier intent and must not revive map B either.
        var staleMapStateRepair = delayedMapB
        staleMapStateRepair.counter = 44
        staleMapStateRepair.subType = .store
        staleMapStateRepair.targetId = rootPlayer.gameModel.gameConfig.id
        await networkMock.handleUpdate(staleMapStateRepair, id: UUID())

        #expect(await rootPlayer.mapRoot.gameController.currentId == mapA)
    }

    @Test func mapStateAdvancesIntentAndAllowsItsTargetedMapRepair() async throws {
        try await setUp()
        try await importTestData(into: rootSut)
        try #require(rootSut.mapRoot.itemController.itemDataModel.items.count >= 2)

        rootSut.adventureRoot.startGame()
        rootPlayer.adventureRoot.startGame()

        let mapA = rootSut.mapRoot.itemController.itemDataModel.items[0]
        let mapB = rootSut.mapRoot.itemController.itemDataModel.items[1]

        await sut.show(for: rootSut.mapRoot.gameController.share(id: mapA))
        var showA = try #require(masterStoreAbstractionMock.sendResponseData as? GameNetworkModel)
        showA.counter = 41

        let mapStateB = rootSut.gameModel.outgoingMessage(
            counter: 42,
            type: .update,
            subType: .mapState,
            asMaster: true,
            data: rootSut.mapRoot.mapGameControllable.networkMapUpdate(for: mapB)
        )
        // Use the same stable, versioned package builder as the production
        // master's targeted repair path. The generic export intentionally does
        // not carry the independent Map asset/content fingerprints.
        let fullMapB = try await rootSut.mapRoot.mapGameControllable.createMapGameData(for: mapB)
        let repairB = rootSut.gameModel.outgoingMessage(
            counter: 43,
            type: .reveal,
            subType: .store,
            asMaster: true,
            targetId: rootPlayer.gameModel.gameConfig.id,
            data: fullMapB
        )
        let masterMapB = rootSut.mapRoot.gameController.gameItem(for: mapB)
        try #require(!masterMapB.entries.isEmpty)
        masterMapB.entries[0].isShown.toggle()
        let expectedRoomVisibility = masterMapB.entries[0].isShown
        let targetedMapStateB = rootSut.gameModel.outgoingMessage(
            counter: 44,
            type: .update,
            subType: .mapState,
            asMaster: true,
            targetId: rootPlayer.gameModel.gameConfig.id,
            data: rootSut.mapRoot.mapGameControllable.networkMapUpdate(for: mapB)
        )

        #expect(mapStateB.data.version == fullMapB.version)
        #expect(targetedMapStateB.data.version == fullMapB.version)
        var legacyTargetedMapStateB = targetedMapStateB
        legacyTargetedMapStateB.data = NetworkCodableDataType(
            id: targetedMapStateB.data.id,
            type: targetedMapStateB.data.type,
            version: 0,
            data: targetedMapStateB.data.data
        )

        networkMock.model.setPlayerDelegate(sutPlayer)
        await networkMock.handleFileUpdate(showA)
        #expect(await rootPlayer.mapRoot.gameController.currentId == mapA)

        // Messenger replies from the logical master must keep the same physical
        // GroupSession participant identity. A different identity is correctly
        // rejected as a same-logical-ID spoof by PlayerController.
        let masterParticipantId = UUID()
        playerStoreAbstractionMock.requestData = nil
        await networkMock.handleUpdate(mapStateB, id: masterParticipantId)
        let requestB = try #require(playerStoreAbstractionMock.requestData as? GameNetworkModel)
        #expect(requestB.type == .reveal)
        #expect(requestB.subType == .mapState)
        #expect(requestB.data.id == mapB)

        await networkMock.handleUpdate(repairB, id: masterParticipantId)

        #expect(await rootPlayer.mapRoot.gameController.currentId == mapB)
        #expect(sutPlayer.gameModel.gameUpdateType == .map)

        await networkMock.handleUpdate(legacyTargetedMapStateB, id: masterParticipantId)

        let playerMapB = rootPlayer.mapRoot.gameController.gameItem(for: mapB)
        try #require(!playerMapB.entries.isEmpty)
        #expect(playerMapB.entries[0].isShown == expectedRoomVisibility)
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
        let firstMapShareData = await rootSut.mapRoot.gameController.shareMap(id: mapId)

        // Prime the exact production state used by a reshow. Building the first
        // package may normalize file metadata, so manually seeding the pre-export
        // fingerprint makes this test depend on whichever test imported the same
        // shared fixture immediately before it.
        await sut.show(for: firstMapShareData)
        let firstMapReveal = try #require(masterStoreAbstractionMock.sendResponseData as? GameNetworkModel)
        #expect(firstMapReveal.data.data != nil)

        masterStoreAbstractionMock.sendResponseData = nil
        let reshowMapShareData = await rootSut.mapRoot.gameController.shareMap(id: mapId)
        await sut.show(for: reshowMapShareData)
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
    }

    @Test func repeatMapRevealUsesMemoryAndRepairsMissingPinPhotosOnce() async throws {
        try await setUp()
        try await importTestData(into: rootSut)
        rootSut.adventureRoot.startGame()
        rootPlayer.adventureRoot.startGame()

        let mapId = try #require(rootSut.mapRoot.itemController.itemDataModel.items.first)
        let mapReference = await rootSut.mapRoot.gameController.shareMap(id: mapId)

        await sut.show(for: mapReference)
        let firstShow = try #require(masterStoreAbstractionMock.sendResponseData as? GameNetworkModel)
        #expect(firstShow.data.data != nil)
        let firstAck = try #require(try await sutPlayer.handle(firstShow))
        #expect(firstAck.subType == .ok)

        let loadedMap = rootPlayer.mapRoot.gameController.gameItem(for: mapId)
        let retainedPin = MapPinModel(
            id: UUID(),
            name: "Retained Player",
            photoId: UUID(),
            isPlayer: true
        )
        loadedMap.mapPins.append(retainedPin)
        sutPlayer.gameModel.gameUpdateType = .space
        playerStoreAbstractionMock.requestData = nil

        let repeatReveal = rootSut.gameModel.outgoingMessage(
            counter: 99,
            type: .reveal,
            subType: .show,
            asMaster: true,
            data: mapReference
        )

        let acknowledgment = try #require(try await sutPlayer.handle(repeatReveal))

        #expect(acknowledgment.subType == .ok)
        #expect(sutPlayer.gameModel.gameUpdateType == .map)
        #expect(rootPlayer.mapRoot.gameController.gameItem(for: mapId) === loadedMap)
        #expect(loadedMap.mapPins.contains { $0.id == retainedPin.id && $0.photoId == retainedPin.photoId })

        // The re-reveal repairs the pin photo that never arrived locally.
        let repairRequest = try #require(playerStoreAbstractionMock.requestData as? GameNetworkModel)
        #expect(repairRequest.type == .store)
        #expect(repairRequest.data.type == .photo)
        #expect(repairRequest.data.id == retainedPin.photoId)

        // A further re-reveal must not request it again — one repair per connection.
        playerStoreAbstractionMock.requestData = nil
        let secondRepeatReveal = rootSut.gameModel.outgoingMessage(
            counter: 100,
            type: .reveal,
            subType: .show,
            asMaster: true,
            data: mapReference
        )
        _ = try #require(try await sutPlayer.handle(secondRepeatReveal))
        #expect(playerStoreAbstractionMock.requestData == nil)
    }

    @Test func mapRevealWithMissingBackgroundRequestsOnlyFullMapOnce() async throws {
        try await setUp()
        try await importTestData(into: rootSut)
        rootSut.adventureRoot.startGame()
        rootPlayer.adventureRoot.startGame()

        let mapId = rootSut.mapRoot.itemController.itemDataModel.items[0]
        let backgroundId = try #require(rootSut.mapRoot.itemController.itemOrEmpty(for: mapId).photoId)
        let mapReference = await rootSut.mapRoot.gameController.share(id: mapId)

        // Deliver the full package once — the map is complete and shows.
        await sut.show(for: mapReference)
        let firstShow = try #require(masterStoreAbstractionMock.sendResponseData as? GameNetworkModel)
        _ = try #require(try await sutPlayer.handle(firstShow))
        #expect(sutPlayer.gameModel.gameUpdateType == .map)
        let advertisedReference = NetworkCodableDataType(
            id: mapId,
            type: .map,
            version: firstShow.data.version,
            assetVersion: firstShow.data.assetVersion,
            contentVersion: firstShow.data.contentVersion
        )

        // Break the background photo on the player: metadata stays, binary gone.
        let background = rootPlayer.photoRoot.gameController.gameItem(for: backgroundId)
        let originalFile = try #require(background.fileUrl)
        let contentHash = try #require(originalFile.contentHash)
        background.fileUrl = FileUrl(
            fileId: originalFile.fileId,
            url: URL(filePath: "/missing/background.png"),
            location: originalFile.location,
            module: originalFile.module,
            relativeUrl: nil,
            contentHash: contentHash
        )
        sutPlayer.gameModel.gameUpdateType = .none
        #expect(
            await rootPlayer.mapRoot.mapGameControllable.mapAssetVersion(for: mapId)
                == advertisedReference.assetVersion
        )
        #expect(
            sutPlayer.gameModel.hasMapContentVersion(
                itemId: mapId,
                contentVersion: advertisedReference.contentVersion
            )
        )
        #expect(await !rootPlayer.mapRoot.mapGameControllable.hasBackgroundImage(itemId: mapId))

        // An incomplete map triggers one full-map re-request; the screen stays.
        let repeatReveal = rootSut.gameModel.outgoingMessage(counter: 99, type: .reveal, subType: .show, asMaster: true, data: advertisedReference)
        let fullMapRequest = try #require(try await sutPlayer.handle(repeatReveal))
        #expect(fullMapRequest.subType == .show)
        #expect(fullMapRequest.data.id == mapId)
        #expect(sutPlayer.gameModel.gameUpdateType == .none)

        // The retry is single-shot. The background never falls through to the
        // pin-photo `.store/.store` repair path.
        playerStoreAbstractionMock.requestData = nil
        playerStoreAbstractionMock.requestHistory = []
        let secondReveal = rootSut.gameModel.outgoingMessage(counter: 100, type: .reveal, subType: .show, asMaster: true, data: advertisedReference)
        let acknowledgment = try await sutPlayer.handle(secondReveal)
        #expect(acknowledgment == nil)
        #expect(sutPlayer.gameModel.gameUpdateType == .none)
        #expect(playerStoreAbstractionMock.requestData == nil)
        #expect(playerStoreAbstractionMock.requestHistory.isEmpty)
        #expect(!sutPlayer.gameModel.requestedRepairIds.contains(backgroundId))
    }

    @Test func stopClearsSentGameMaps() async throws {
        try await setUp()
        try await importTestData(into: rootSut)
        rootSut.adventureRoot.startGame()

        let mapId = rootSut.mapRoot.itemController.itemDataModel.items[0]
        let mapShareData = await rootSut.mapRoot.gameController.shareMap(id: mapId)
        await sut.show(for: mapShareData)
        #expect(
            sut.gameModel.hasSentGameItem(
                type: .map,
                id: mapId,
                version: mapShareData.effectiveAssetVersion
            )
        )

        await sut.stop()
        #expect(sut.gameModel.sentGameItems.isEmpty)
    }

    // MARK: - Invisible proxy routing

    private func proxyMessage(
        counter: Int = 3,
        type: RPGMessageType,
        subType: RPGMessageActionType,
        data: NetworkCodableDataType,
        remoteId: UUID,
        purpose: GameMessagePurpose = .event
    ) -> GameNetworkModel {
        GameNetworkModel(
            counter: counter,
            proxyCounter: 1,
            type: type,
            subType: subType,
            masterId: gameConfigModelPlayer.master.id,
            sender: GameSenderModel(
                id: remoteId,
                role: .proxy,
                name: "Proxy Mirror",
                characterId: nil
            ),
            purpose: purpose,
            data: data
        )
    }

    @Test func proxyAnnouncementsAreConsumed() async throws {
        try await setUp()
        rootPlayer.gameModel.playerController = sutPlayer
        rootPlayer.adventureRoot.startGame()
        let proxyMaster = try #require(sutPlayer.proxyMasterController)
        let remoteId = UUID()

        let connectionId = ConnectionController.ID()
        await proxyMaster.receivedServerProxy(proxyMessage(counter: 1, type: .reveal, subType: .ok, data: NetworkCodableDataType(id: UUID(), type: .photo, version: 0), remoteId: remoteId), connectionId: connectionId)
        await proxyMaster.receivedServerProxy(proxyMessage(counter: 2, type: .update, subType: .store, data: NetworkCodableDataType(id: UUID(), type: .value, version: 0, data: Data([1])), remoteId: remoteId), connectionId: connectionId)
        await proxyMaster.receivedServerProxy(proxyMessage(counter: 3, type: .update, subType: .audioList, data: NetworkCodableDataType(id: UUID(), type: .audio, version: 0, data: Data([2])), remoteId: remoteId), connectionId: connectionId)
        await proxyMaster.receivedServerProxy(proxyMessage(counter: 4, type: .store, subType: .screen, data: NetworkCodableDataType(id: UUID(), type: .game, version: 0, data: Data([3])), remoteId: remoteId), connectionId: connectionId)

        #expect(playerStoreAbstractionMock.calledRequest == 0)
        #expect(!rootPlayer.gameModel.gameRoster.players.contains { $0.id == remoteId })
    }

    @Test func proxyMapPinUpdatesHostMapFirstAndRemaps() async throws {
        try await setUp()
        try await importTestData(into: rootPlayer)
        rootPlayer.gameModel.playerController = sutPlayer
        rootPlayer.adventureRoot.startGame()
        let proxyMaster = try #require(sutPlayer.proxyMasterController)

        let mapId = rootPlayer.mapRoot.itemController.itemDataModel.items[0]
        _ = await rootPlayer.mapRoot.gameController.setCurrent(itemId: mapId)
        let remoteId = UUID()
        let pinId = gameConfigModelPlayer.id
        let currentPin = MapPinModel(
            id: pinId,
            name: "Proxy Pin",
            isPlayer: true,
            players: [pinId],
            timeInterval: 1
        )
        rootPlayer.mapRoot.gameController.gameItem(for: mapId).mapPins.append(currentPin)
        rootPlayer.mapRoot.gameController.mapGameModel.playerPins.append(currentPin)
        var pin = currentPin
        pin.location = CGPoint(x: 5, y: 6)
        pin.timeInterval = 99
        let mapReference = await rootPlayer.mapRoot.gameController.shareMap(id: mapId)
        let pinData = NetworkCodableDataType(
            id: mapId,
            type: .map,
            version: mapReference.version,
            data: pin.encodeData(),
            assetVersion: mapReference.assetVersion,
            contentVersion: mapReference.contentVersion
        )

        await proxyMaster.receivedServerProxy(
            proxyMessage(type: .update, subType: .mapPin, data: pinData, remoteId: remoteId),
            connectionId: UUID()
        )

        // The host's own map updates first, then the same pin leaves as the host's update.
        #expect(rootPlayer.mapRoot.gameController.gameItem(for: mapId).mapPins.first { $0.id == pin.id }?.location == pin.location)
        let forwarded = try #require(playerStoreAbstractionMock.requestData as? GameNetworkModel)
        #expect(forwarded.subType == .mapPin)
        #expect(forwarded.sender.id == gameConfigModelPlayer.id)
        #expect(forwarded.data.id == mapId)
    }

    @Test func proxyPhotoRequestIsServedByHost() async throws {
        try await setUp()
        try await importTestData(into: rootPlayer)
        try await importPhotoTestData(into: rootPlayer)
        rootPlayer.gameModel.playerController = sutPlayer
        rootPlayer.adventureRoot.startGame()

        let proxyMasterSpy = MasterNetworkControllableMock()
        rootPlayer.networkProxyStore = GameNetworkController(
            name: "ProxySpy",
            proxy: true,
            masterBuilder: { _, _ in proxyMasterSpy },
            playerBuilder: { _, _ in PlayerStoreAbstractionMock() }
        )
        let proxyMaster = try #require(sutPlayer.proxyMasterController)
        let photoId = rootPlayer.photoRoot.itemController.itemDataModel.items[0]
        let reference = await rootPlayer.photoRoot.gameControllable.share(id: photoId)
        let remoteId = UUID()
        let connectionId = ConnectionController.ID()

        await proxyMaster.receivedServerProxy(
            proxyMessage(
                type: .reveal,
                subType: .show,
                data: reference,
                remoteId: remoteId,
                purpose: .assetRequest
            ),
            connectionId: connectionId
        )

        // A matching local version is returned only over the requesting proxy
        // connection; sibling private mirrors do not download the repair.
        let served = try #require(proxyMasterSpy.sendResponseData as? GameNetworkModel)
        #expect(proxyMasterSpy.calledSendResponseId == 1)
        #expect(proxyMasterSpy.calledSendResponseAll == 0)
        #expect(served.sender.id == rootPlayer.gameModel.gameConfig.master.id)
        #expect(served.masterId == rootPlayer.gameModel.gameConfig.master.id)
        #expect(served.sender.isMaster)
        #expect(served.targetId == remoteId)
        #expect(served.data.id == photoId)
        #expect(served.data.effectiveAssetVersion == reference.effectiveAssetVersion)
        #expect(served.data.data != nil)
        #expect(playerStoreAbstractionMock.calledRequest == 0)
    }

    @Test func proxyPhotoPresentationIsRemappedEvenWhenHostHasData() async throws {
        try await setUp()
        try await importPhotoTestData(into: rootPlayer)
        rootPlayer.gameModel.playerController = sutPlayer
        rootPlayer.adventureRoot.startGame()
        let proxyMaster = try #require(sutPlayer.proxyMasterController)
        let photoId = rootPlayer.photoRoot.itemController.itemDataModel.items[0]
        let reference = await rootPlayer.photoRoot.gameControllable.share(id: photoId)

        await proxyMaster.receivedServerProxy(
            proxyMessage(
                type: .reveal,
                subType: .show,
                data: reference,
                remoteId: UUID(),
                purpose: .event
            ),
            connectionId: UUID()
        )

        let forwarded = try #require(playerStoreAbstractionMock.requestData as? GameNetworkModel)
        #expect(forwarded.purpose == .event)
        #expect(forwarded.sender.id == gameConfigModelPlayer.id)
        #expect(forwarded.data.id == photoId)
        #expect(forwarded.data.data == nil)
    }

    @Test(
        "Proxy file presentation reaches host and sibling mirrors with one upstream send",
        arguments: [NetworkModules.photo, .pdf, .space]
    )
    func proxyFilePresentationFansOutOnce(module: NetworkModules) async throws {
        try await setUp()
        switch module {
        case .photo:
            try await importPhotoTestData(into: rootPlayer)
        case .pdf:
            try await MockRoot.importTestData(
                into: rootPlayer.adventureRoot,
                name: ResourcesDebug.pdfTestData,
                itemCounter: 0
            )
        case .space:
            try await importSpaceTestData(into: rootPlayer)
        default:
            Issue.record("Unexpected proxy presentation module \(module)")
            return
        }

        rootPlayer.adventureRoot.startGame()
        rootPlayer.gameModel.playerController = sutPlayer

        let proxyMasterSpy = MasterNetworkControllableMock()
        rootPlayer.networkProxyStore = GameNetworkController(
            name: "Proxy sibling relay",
            proxy: true,
            masterBuilder: { _, _ in proxyMasterSpy },
            playerBuilder: { _, _ in PlayerStoreAbstractionMock() }
        )

        let itemId: UUID
        let fullData: NetworkCodableDataType
        let masterId = rootPlayer.gameModel.gameConfig.master.id
        switch module {
        case .photo:
            itemId = try #require(rootPlayer.photoRoot.itemController.itemDataModel.items.first)
            fullData = try await rootPlayer.photoRoot.gameControllable.createGameData(for: itemId)
            await rootPlayer.photoRoot.photoGameControllable.setMasterVersion(
                itemId: itemId,
                version: fullData.effectiveAssetVersion,
                masterId: masterId
            )
        case .pdf:
            itemId = try #require(rootPlayer.pdfRoot.itemController.itemDataModel.items.first)
            fullData = try await rootPlayer.pdfRoot.gameControllable.createGameData(for: itemId)
            await rootPlayer.pdfRoot.pdfGameControllable.setMasterVersion(
                itemId: itemId,
                version: fullData.effectiveAssetVersion,
                masterId: masterId
            )
        case .space:
            itemId = try #require(rootPlayer.spaceRoot.itemController.itemDataModel.items.first)
            fullData = try await rootPlayer.spaceRoot.gameControllable.createGameData(for: itemId)
            await rootPlayer.spaceRoot.spaceGameControllable.setMasterVersion(
                itemId: itemId,
                version: fullData.effectiveAssetVersion,
                masterId: masterId
            )
        default:
            return
        }

        let connectionId = ConnectionController.ID()
        let proxyMaster = try #require(sutPlayer.proxyMasterController)
        let upstreamBefore = playerStoreAbstractionMock.calledRequest
        await proxyMaster.receivedServerProxy(
            proxyMessage(
                type: .reveal,
                subType: .show,
                data: fullData,
                remoteId: UUID(),
                purpose: .event
            ),
            connectionId: connectionId
        )

        // The host identity and counter are minted once, then reused upstream
        // and for sibling mirrors. The source mirror is deliberately excluded.
        #expect(playerStoreAbstractionMock.calledRequest == upstreamBefore + 1)
        let upstream = try #require(playerStoreAbstractionMock.requestData as? GameNetworkModel)
        #expect(proxyMasterSpy.calledSendResponseExcept == 1)
        #expect(proxyMasterSpy.calledSendResponseAll == 0)
        #expect(proxyMasterSpy.lastExceptId == connectionId)
        let sibling = try #require(proxyMasterSpy.sendResponseExceptData as? GameNetworkModel)
        #expect(sibling.sender.id == gameConfigModelPlayer.id)
        #expect(sibling.counter == upstream.counter)
        #expect(sibling.data.id == itemId)
        #expect(sibling.data.type == module)

        #expect(sutPlayer.gameModel.gameUpdateType == module)
        let currentItemId: UUID? = switch module {
        case .photo:
            await rootPlayer.photoRoot.gameControllable.gameModel.currentItemId
        case .pdf:
            await rootPlayer.pdfRoot.gameControllable.gameModel.currentItemId
        case .space:
            await rootPlayer.spaceRoot.gameControllable.gameModel.currentItemId
        default:
            nil
        }
        #expect(currentItemId == itemId)
    }

    @Test func staleProxyPhotoRequestIsRemappedToMaster() async throws {
        try await setUp()
        try await importPhotoTestData(into: rootPlayer)
        rootPlayer.gameModel.playerController = sutPlayer
        rootPlayer.adventureRoot.startGame()
        let proxyMaster = try #require(sutPlayer.proxyMasterController)
        let photoId = rootPlayer.photoRoot.itemController.itemDataModel.items[0]
        let reference = await rootPlayer.photoRoot.gameControllable.share(id: photoId)
        let staleRequest = NetworkCodableDataType(
            id: photoId,
            type: .photo,
            version: reference.effectiveAssetVersion + 1
        )

        await proxyMaster.receivedServerProxy(
            proxyMessage(
                type: .reveal,
                subType: .show,
                data: staleRequest,
                remoteId: UUID(),
                purpose: .assetRequest
            ),
            connectionId: UUID()
        )

        let forwarded = try #require(playerStoreAbstractionMock.requestData as? GameNetworkModel)
        #expect(forwarded.purpose == .assetRequest)
        #expect(forwarded.data.effectiveAssetVersion == staleRequest.effectiveAssetVersion)
        #expect(forwarded.data.data == nil)
    }

    @Test func staleFileBackedProxyRequestsAreNeverServedFromHostCache() async throws {
        try await setUp()
        try await MockRoot.importTestData(
            into: rootPlayer.adventureRoot,
            name: ResourcesDebug.audioTestData,
            itemCounter: 0
        )
        try await MockRoot.importTestData(
            into: rootPlayer.adventureRoot,
            name: ResourcesDebug.pdfTestData,
            itemCounter: 0
        )
        try await importPhotoTestData(into: rootPlayer)
        try await importSpaceTestData(into: rootPlayer)
        rootPlayer.gameModel.playerController = sutPlayer
        rootPlayer.adventureRoot.startGame()
        let proxyMaster = try #require(sutPlayer.proxyMasterController)

        let audioId = try #require(rootPlayer.audioRoot.itemController.itemDataModel.items.first)
        let pdfId = try #require(rootPlayer.pdfRoot.itemController.itemDataModel.items.first)
        let photoId = try #require(rootPlayer.photoRoot.itemController.itemDataModel.items.first)
        let spaceId = try #require(rootPlayer.spaceRoot.itemController.itemDataModel.items.first)
        let references = [
            await rootPlayer.audioRoot.gameControllable.share(id: audioId),
            await rootPlayer.pdfRoot.gameControllable.share(id: pdfId),
            await rootPlayer.photoRoot.gameControllable.share(id: photoId),
            await rootPlayer.spaceRoot.gameControllable.share(id: spaceId)
        ]

        for (offset, reference) in references.enumerated() {
            let stale = NetworkCodableDataType(
                id: reference.id,
                type: reference.type,
                version: reference.effectiveAssetVersion + 1
            )
            await proxyMaster.receivedServerProxy(
                proxyMessage(
                    counter: 20 + offset,
                    type: .reveal,
                    subType: .show,
                    data: stale,
                    remoteId: UUID(),
                    purpose: .assetRequest
                ),
                connectionId: UUID()
            )

            let forwarded = try #require(playerStoreAbstractionMock.requestData as? GameNetworkModel)
            #expect(forwarded.data.type == reference.type)
            #expect(forwarded.data.effectiveAssetVersion == stale.effectiveAssetVersion)
            #expect(forwarded.purpose == .assetRequest)
        }

        #expect(playerStoreAbstractionMock.calledRequest == references.count)
    }

    @Test func proxyPhotoRequestIsRemappedWhenHostLacksData() async throws {
        try await setUp()
        try await importTestData(into: rootPlayer)
        try await importPhotoTestData(into: rootPlayer)
        rootPlayer.gameModel.playerController = sutPlayer
        rootPlayer.adventureRoot.startGame()
        let proxyMaster = try #require(sutPlayer.proxyMasterController)

        let photoId = rootPlayer.photoRoot.itemController.itemDataModel.items[0]
        // The host itself lacks the binary — it must ask the master instead.
        rootPlayer.photoRoot.gameController.gameItem(for: photoId).fileUrl = FileUrl(
            fileId: UUID(),
            url: URL(filePath: "/missing/photo.png"),
            location: .local,
            module: "photo",
            relativeUrl: nil
        )
        let remoteId = UUID()

        await proxyMaster.receivedServerProxy(
            proxyMessage(
                type: .reveal,
                subType: .show,
                data: NetworkCodableDataType(id: photoId, type: .photo, version: 0),
                remoteId: remoteId,
                purpose: .assetRequest
            ),
            connectionId: UUID()
        )

        let forwarded = try #require(playerStoreAbstractionMock.requestData as? GameNetworkModel)
        #expect(forwarded.sender.id == gameConfigModelPlayer.id)
        #expect(forwarded.type == .reveal)
        #expect(forwarded.purpose == .assetRequest)
        #expect(forwarded.data.id == photoId)
        #expect(forwarded.data.data == nil)
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
        let sendedShowPhotoData = try #require(masterStoreAbstractionMock.sendResponseData as? GameNetworkModel)
        #expect(sendedShowPhotoData.data.data != nil)
        #expect(sendedShowPhotoData.data.version == version)
        #expect(sendedShowPhotoData.usesFileJournal)

        var result = try await sutPlayer.handle(sendedShowPhotoData)
        #expect(nil != result)
        #expect(result!.subType == .ok)
        #expect(await rootPlayer.photoRoot.gameController.currentId == photoId)
        #expect(rootPlayer.photoRoot.gameController.gameItem(for: photoId).version == version)

        // a reshow announces the photo only by reference
        await sut.show(for: photoShareData)
        let reshowReference = try #require(masterStoreAbstractionMock.sendResponseData as? GameNetworkModel)
        #expect(reshowReference.data.id == photoId)
        #expect(reshowReference.data.data == nil)
        result = try await sutPlayer.handle(reshowReference)
        #expect(result?.subType == .ok)
    }

    @Test func reshowingAnEarlierPhotoAfterANewerOneStillWorks() async throws {
        try await setUp()
        try await importTestData(into: rootSut)
        try await importPhotoTestData(into: rootSut)

        rootSut.adventureRoot.startGame()
        rootPlayer.adventureRoot.startGame()

        let photoA = rootSut.photoRoot.itemController.itemDataModel.items[0]
        let photoB = rootSut.photoRoot.itemController.itemDataModel.items[1]

        // Show photo A fully.
        await sut.show(for: rootSut.photoRoot.gameController.share(id: photoA))
        let showA = try #require(masterStoreAbstractionMock.sendResponseData as? GameNetworkModel)
        #expect(showA.data.data != nil)
        _ = try await sutPlayer.handle(showA)
        #expect(await rootPlayer.photoRoot.gameController.currentId == photoA)

        // Show a different photo B fully — replaces the journal attachment / current item.
        await sut.show(for: rootSut.photoRoot.gameController.share(id: photoB))
        let showB = try #require(masterStoreAbstractionMock.sendResponseData as? GameNetworkModel)
        #expect(showB.data.data != nil)
        _ = try await sutPlayer.handle(showB)
        #expect(await rootPlayer.photoRoot.gameController.currentId == photoB)

        // Reshow the OLDER photo A — master already sent it once, so this is
        // reference-only; the player must still be able to show it from memory.
        await sut.show(for: rootSut.photoRoot.gameController.share(id: photoA))
        let reshowA = try #require(masterStoreAbstractionMock.sendResponseData as? GameNetworkModel)
        #expect(reshowA.data.id == photoA)
        #expect(reshowA.data.data == nil)

        let result = try await sutPlayer.handle(reshowA)
        #expect(result?.subType == .ok, "expected an ok ack, got \(String(describing: result?.subType))")
        #expect(await rootPlayer.photoRoot.gameController.currentId == photoA)
    }

    @Test func repairRequestForAnOldPhotoGetsTheCorrectPhotoBack() async throws {
        try await setUp()
        try await importTestData(into: rootSut)
        try await importPhotoTestData(into: rootSut)

        rootSut.adventureRoot.startGame()
        rootPlayer.adventureRoot.startGame()

        let photoA = rootSut.photoRoot.itemController.itemDataModel.items[0]
        let photoB = rootSut.photoRoot.itemController.itemDataModel.items[1]

        // Master shows A fully, but the player's download/import never lands —
        // e.g. the SharePlay journal attachment got replaced mid-download.
        // Master still marks A as sent since export succeeded on its end.
        await sut.show(for: rootSut.photoRoot.gameController.share(id: photoA))
        _ = try #require(masterStoreAbstractionMock.sendResponseData as? GameNetworkModel)

        // Master shows a different photo B fully — this one the player does receive.
        await sut.show(for: rootSut.photoRoot.gameController.share(id: photoB))
        let showB = try #require(masterStoreAbstractionMock.sendResponseData as? GameNetworkModel)
        // Use the real receive pipeline so this first accepted master envelope
        // also pins the player's session authority. Calling `handle` directly
        // skips that security boundary and manufactures a later repair request
        // whose master ID is still empty.
        playerStoreAbstractionMock.requestData = nil
        await sutPlayer.receivedProcess(showB)
        _ = try #require(playerStoreAbstractionMock.requestData as? GameNetworkModel)
        #expect(await rootPlayer.photoRoot.gameController.currentId == photoB)

        // Master reshows A — already marked sent, so only the reference goes out.
        await sut.show(for: rootSut.photoRoot.gameController.share(id: photoA))
        let reshowA = try #require(masterStoreAbstractionMock.sendResponseData as? GameNetworkModel)
        #expect(reshowA.data.id == photoA)
        #expect(reshowA.data.data == nil)

        // The player never actually has A, so it must ask for the full payload.
        playerStoreAbstractionMock.requestData = nil
        await sutPlayer.receivedProcess(reshowA)
        let request = try #require(playerStoreAbstractionMock.requestData as? GameNetworkModel)
        #expect(request.subType == .show)
        #expect(request.data.id == photoA)
        #expect(request.data.data == nil)

        // Route the request through the master's full receive pipeline, exactly
        // like the network layer would.
        await sut.receivedProcess(request, connectionId: nil)
        let repairResponse = try #require(masterStoreAbstractionMock.sendResponseData as? GameNetworkModel)

        // The master's answer must be for the REQUESTED photo (A), not whatever
        // else happens to be current — and it must carry the actual bytes.
        #expect(repairResponse.data.id == photoA, "master answered with \(repairResponse.data.id) instead of the requested \(photoA)")
        #expect(repairResponse.data.data != nil)
        #expect(repairResponse.targetId == gameConfigModelPlayer.id)

        playerStoreAbstractionMock.requestData = nil
        await sutPlayer.receivedProcess(repairResponse)
        let finalAck = try #require(playerStoreAbstractionMock.requestData as? GameNetworkModel)
        #expect(finalAck.subType == .ok)
        #expect(await rootPlayer.photoRoot.gameController.currentId == photoA)
    }

    @Test func photoRevealAckUpdatesMasterMessageLog() async throws {
        try await setUp()
        try await importTestData(into: rootSut)
        try await importPhotoTestData(into: rootSut)

        rootSut.adventureRoot.startGame()
        rootPlayer.adventureRoot.startGame()

        // Seed the roster so the pending row's delivery state is meaningful —
        // with zero known players "missing" and "all" are indistinguishable.
        rootSut.gameModel.gameRoster.players = [PlayerGameModel(id: gameConfigModelPlayer.id, type: .player, name: "AndrenalinPlayer")]

        let photoId = rootSut.photoRoot.itemController.itemDataModel.items[0]
        let photoShareData = await rootSut.photoRoot.gameController.share(id: photoId)
        await sut.show(for: photoShareData)
        let sendedShowPhotoData = try #require(masterStoreAbstractionMock.sendResponseData as? GameNetworkModel)

        // Before any acknowledgement travels back, the row the master logged
        // for this send shows nobody has confirmed it yet.
        let pendingRow = try #require(rootSut.logGameController.logRows.first)
        #expect(pendingRow.deliveryState == .missingPlayers)

        // Receiving through the controller pipeline establishes the master
        // session before constructing the acknowledgement. A direct module
        // `handle` call deliberately bypasses that authentication state.
        playerStoreAbstractionMock.requestData = nil
        await sutPlayer.receivedProcess(sendedShowPhotoData)
        let ack = try #require(playerStoreAbstractionMock.requestData as? GameNetworkModel)
        #expect(ack.subType == .ok)
        // The ack must echo the original send's counter — with a fresh
        // player-local counter this round trip silently updates no row at all.
        #expect(ack.counter == sendedShowPhotoData.counter)

        // Route the ack through the master's full receive pipeline, exactly
        // like the network layer would, so `updateMessage` actually runs.
        await sut.receivedProcess(ack, connectionId: nil)

        let updatedRow = try #require(rootSut.logGameController.logRows.first)
        #expect(updatedRow.deliveryState == .allPlayers)
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
        // Player bytes never replace the gamemaster's canonical baseline. This
        // master has no photo with that ID, so it neither imports nor reports
        // the player's private asset.
        #expect(!playerPhotoEnv.masterRoot.photoRoot.gameController.gameModel.items.contains(playerPhotoId))
        #expect(playerPhotoEnv.masterRoot.photoRoot.itemController.itemSync(for: playerPhotoId, noGame: true) == nil)
        #expect(playerPhotoEnv.playerRoot.photoRoot.itemController.itemOrEmpty(for: playerPhotoId).version == playerPhotoVersion)
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
        // Player bytes never replace the gamemaster's canonical baseline. This
        // master has no photo with that ID, so it neither imports nor reports
        // the player's private asset.
        #expect(!playerPhotoEnv.masterRoot.photoRoot.gameController.gameModel.items.contains(playerPhotoId))
        #expect(playerPhotoEnv.masterRoot.photoRoot.itemController.itemSync(for: playerPhotoId, noGame: true) == nil)
        #expect(playerPhotoEnv.playerRoot.photoRoot.itemController.itemOrEmpty(for: playerPhotoId).version == playerPhotoVersion)
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
        let sendedShowSpaceData = try #require(masterStoreAbstractionMock.sendResponseData as? GameNetworkModel)
        #expect(sendedShowSpaceData.data.data != nil)
        #expect(sendedShowSpaceData.data.version == version)

        let result = try await sutPlayer.handle(sendedShowSpaceData)
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

    @discardableResult
    func sendResponse(data: MessageMapper?, id: ConnectionController.ID) async -> Bool {
        guard id == link?.connectionId else { return false }
        await link?.relayMasterToPlayer(data)
        return true
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

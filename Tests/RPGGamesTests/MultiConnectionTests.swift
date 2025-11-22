// @copyright André Trettin

#if canImport(Testing)
import AndrenalinKit
import Foundation
import RPGResourcesDebug
import Testing

@testable import RPGGame

@testable import RPGDie
@testable import AudioRPG
@testable import RPGMaps
@testable import PhotoRPG
@testable import SpaceRPG
@testable import RPGTables
@testable import RPGValues

final class MultiConntectionTests {
    private var sut: MasterController!
    private var rootSut: GameRoot!
    private var gameConfigModelSut: GameConfigModel!

    private var sutPlayer: PlayerController!
    private var rootPlayer: GameRoot!
    private var gameConfigModelPlayer: GameConfigModel!

    private var sut2Player: PlayerController!
    private var root2Player: GameRoot!
    private var gameConfigModel2Player: GameConfigModel!

    private var sut3Player: PlayerController!
    private var root3Player: GameRoot!
    private var gameConfigModel3Player: GameConfigModel!

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
        gameConfigModelPlayer = GameConfigModel(id: playerId, state: .started, master: .empty, players: [PlayerGameModel(id: playerId, type: .player, name: "Player - 1")], controls: [])
        await rootPlayer.gameModel.reset(gameConfig: gameConfigModelPlayer)
        sutPlayer = await PlayerController(root: rootPlayer, asGameMaster: false)
        
        root2Player = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: root2Player.adventureRoot)
        try await MockRoot.resetGameController(for: root2Player)
        root2Player.networkStore = networkMock

        let playerId2 = UUID()
        gameConfigModel2Player = GameConfigModel(id: playerId2, state: .started, master: .empty, players: [PlayerGameModel(id: playerId2, type: .player, name: "Player - 2")], controls: [])
        await root2Player.gameModel.reset(gameConfig: gameConfigModel2Player)
        sut2Player = await PlayerController(root: root2Player, asGameMaster: false)

        root3Player = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: root3Player.adventureRoot)
        try await MockRoot.resetGameController(for: root3Player)
        
        root3Player.networkStore = networkMock
        let playerId3 = UUID()
        gameConfigModel3Player = GameConfigModel(id: playerId3, state: .started, master: .empty, players: [PlayerGameModel(id: playerId3, type: .player, name: "Player - 3")], controls: [])
        await root3Player.gameModel.reset(gameConfig: gameConfigModel3Player)
        sut3Player = await PlayerController(root: root3Player, asGameMaster: false)
    }
    
    @Test func handleAudio() async throws {
        try await setUp()
        try await MockRoot.importTestData(into: rootSut.adventureRoot)
        try await MockRoot.importTestData(into: rootSut.adventureRoot, name: ResourcesDebug.audioTestData, itemCounter: 3)
        try await #require(rootSut.audioRoot.itemController.itemDataModel.items.count == 2)

        // send show audio
        let audioId = await rootSut.audioRoot.itemController.itemDataModel.items[1]
        let version = await rootSut.audioRoot.itemController.itemOrEmpty(for: audioId).version
        await #expect(rootSut.audioRoot.itemController.itemOrEmpty(for: audioId).entries.isEmpty)
        let audioShareData = await rootSut.audioRoot.gameController.share(id: audioId)
        await sut.show(for: audioShareData)
        var sendedShowAudioData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(nil != sendedShowAudioData)

        // send all player
        await sutPlayer.receivedProcess(sendedShowAudioData!)
        var respondedShowAudioData1 = playerStoreAbstractionMock.requestData as? GameNetworkModel
        #expect(nil != respondedShowAudioData1)
        #expect(respondedShowAudioData1!.subType == .show)
        await #expect(rootPlayer.audioRoot.gameController.currentId != audioId)
        await #expect(rootPlayer.gameModel.gameConfig.master == gameConfigModelSut.master)
        await #expect(rootPlayer.gameModel.gameConfig.players == gameConfigModelPlayer.players)
        var sutControls = await rootSut.gameModel.gameConfig.controls
        await #expect(rootPlayer.gameModel.gameConfig.controls == sutControls)

        await sut2Player.receivedProcess(sendedShowAudioData!)
        var respondedShowAudioData2 = playerStoreAbstractionMock.requestData as? GameNetworkModel
        #expect(nil != respondedShowAudioData2)
        #expect(respondedShowAudioData2!.subType == .show)
        await #expect(root2Player.audioRoot.gameController.currentId != audioId)
        await #expect(root2Player.gameModel.gameConfig.master == gameConfigModelSut.master)
        await #expect(root2Player.gameModel.gameConfig.players == gameConfigModel2Player.players)
        sutControls = await rootSut.gameModel.gameConfig.controls
        await #expect(root2Player.gameModel.gameConfig.controls == sutControls)

        await sut3Player.receivedProcess(sendedShowAudioData!)
        var respondedShowAudioData3 = playerStoreAbstractionMock.requestData as? GameNetworkModel
        #expect(nil != respondedShowAudioData3)
        #expect(respondedShowAudioData3!.subType == .show)
        await #expect(root3Player.audioRoot.gameController.currentId != audioId)
        await #expect(root3Player.gameModel.gameConfig.master == gameConfigModelSut.master)
        await #expect(root3Player.gameModel.gameConfig.players == gameConfigModel3Player.players)
        sutControls = await rootSut.gameModel.gameConfig.controls
        await #expect(root3Player.gameModel.gameConfig.controls == sutControls)

        // response from players
        await sut.receivedProcess(respondedShowAudioData1!, connectionId: nil)
        sendedShowAudioData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(nil != sendedShowAudioData)
        #expect(nil != sendedShowAudioData?.data)
        #expect(sendedShowAudioData!.data.id == audioId)
        #expect(sendedShowAudioData!.data.type == .audio)
        #expect(sendedShowAudioData!.data.version == version)
        await #expect(rootSut.gameModel.gameConfig.master == gameConfigModelSut.master)
        await #expect(rootSut.gameModel.gameConfig.players == gameConfigModelPlayer.players)
        await #expect(rootSut.gameModel.gameConfig.controls == [SharingControlModel(id: gameConfigModelPlayer.id, name: gameConfigModelPlayer.name, show: true)])

        await sut.receivedProcess(respondedShowAudioData3!, connectionId: nil)
        let sendedShowAudioData3 = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(nil != sendedShowAudioData3)
        #expect(nil != sendedShowAudioData3?.data)
        #expect(sendedShowAudioData3!.data.id == audioId)
        #expect(sendedShowAudioData3!.data.type == .audio)
        #expect(sendedShowAudioData3!.data.version == version)
        await #expect(rootSut.gameModel.gameConfig.master == gameConfigModelSut.master)
        await #expect(rootSut.gameModel.gameConfig.players == [gameConfigModelPlayer.players[0], gameConfigModel3Player.players[0]])
        await #expect(rootSut.gameModel.gameConfig.controls == [
            SharingControlModel(id: gameConfigModelPlayer.id, name: gameConfigModelPlayer.name, show: true),
            SharingControlModel(id: gameConfigModel3Player.id, name: gameConfigModel3Player.name, show: true)
        ])

        // player1 process audio
        await sutPlayer.receivedProcess(sendedShowAudioData!)
        respondedShowAudioData1 = playerStoreAbstractionMock.requestData as? GameNetworkModel
        #expect(nil != respondedShowAudioData1)
        #expect(respondedShowAudioData1!.subType == .ok)
        await #expect(rootPlayer.audioRoot.gameController.currentId == audioId)
        await #expect(rootPlayer.gameModel.gameConfig.master == gameConfigModelSut.master)
        await #expect(rootPlayer.gameModel.gameConfig.players == gameConfigModelPlayer.players)
        await #expect(rootPlayer.gameModel.gameConfig.controls == [
            SharingControlModel(id: gameConfigModelPlayer.id, name: gameConfigModelPlayer.name, show: true)
        ])
        await #expect(rootPlayer.audioRoot.gameController.currentId == audioId)
        await #expect(rootPlayer.audioRoot.gameController.gameItem(for: audioId).version == version)
        await #expect(rootPlayer.audioRoot.itemController.itemDataModel.items.count == 1)
        
        // player2 response
        await sut.receivedProcess(respondedShowAudioData2!, connectionId: nil)
        let sendedShowAudioData2 = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(nil != sendedShowAudioData2)
        #expect(nil != sendedShowAudioData2?.data)
        #expect(sendedShowAudioData2!.data.id == audioId)
        #expect(sendedShowAudioData2!.data.type == .audio)
        #expect(sendedShowAudioData2!.data.version == version)
        await #expect(rootSut.gameModel.gameConfig.master == gameConfigModelSut.master)
        await #expect(rootSut.gameModel.gameConfig.players == [gameConfigModelPlayer.players[0], gameConfigModel3Player.players[0], gameConfigModel2Player.players[0]])
        await #expect(rootSut.gameModel.gameConfig.controls == [
            SharingControlModel(id: gameConfigModelPlayer.id, name: gameConfigModelPlayer.name, show: true),
            SharingControlModel(id: gameConfigModel3Player.id, name: gameConfigModel3Player.name, show: true),
            SharingControlModel(id: gameConfigModel2Player.id, name: gameConfigModel2Player.name, show: true)
        ])
        
        // player2 process audio
        await sut2Player.receivedProcess(sendedShowAudioData2!)
        respondedShowAudioData2 = playerStoreAbstractionMock.requestData as? GameNetworkModel
        #expect(nil != respondedShowAudioData2)
        #expect(respondedShowAudioData2!.subType == .ok)
        await #expect(root2Player.audioRoot.gameController.currentId == audioId)
        await #expect(root2Player.gameModel.gameConfig.master == gameConfigModelSut.master)
        await #expect(root2Player.gameModel.gameConfig.players == [gameConfigModelPlayer.players[0], gameConfigModel3Player.players[0], gameConfigModel2Player.players[0]])
        await #expect(root2Player.gameModel.gameConfig.controls == [
                SharingControlModel(id: gameConfigModelPlayer.id, name: gameConfigModelPlayer.name, show: true),
                SharingControlModel(id: gameConfigModel3Player.id, name: gameConfigModel3Player.name, show: true),
                SharingControlModel(id: gameConfigModel2Player.id, name: gameConfigModel2Player.name, show: true)
        ])
        await #expect(root2Player.audioRoot.gameController.currentId == audioId)
        await #expect(root2Player.audioRoot.gameController.gameItem(for: audioId).version == version)
        await #expect(root2Player.audioRoot.itemController.itemDataModel.items.count == 1)

        // player3 process audio
        await sut3Player.receivedProcess(sendedShowAudioData3!)
        respondedShowAudioData3 = playerStoreAbstractionMock.requestData as? GameNetworkModel
        #expect(nil != respondedShowAudioData3)
        #expect(respondedShowAudioData3!.subType == .ok)
        await #expect(root3Player.audioRoot.gameController.currentId == audioId)
        await #expect(root3Player.gameModel.gameConfig.master == gameConfigModelSut.master)
        await #expect(root3Player.gameModel.gameConfig.players == [gameConfigModelPlayer.players[0], gameConfigModel3Player.players[0]])
        await #expect(root3Player.gameModel.gameConfig.controls == [
                SharingControlModel(id: gameConfigModelPlayer.id, name: gameConfigModelPlayer.name, show: true),
                SharingControlModel(id: gameConfigModel3Player.id, name: gameConfigModel3Player.name, show: true)
        ])
        await #expect(root3Player.audioRoot.gameController.currentId == audioId)
        await #expect(root3Player.audioRoot.gameController.gameItem(for: audioId).version == version)
        await #expect(root3Player.audioRoot.itemController.itemDataModel.items.count == 1)
        
        // status code are send back
        masterStoreAbstractionMock.sendResponseData = nil
        await sut.receivedProcess(respondedShowAudioData3!, connectionId: nil)
        sendedShowAudioData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(nil != sendedShowAudioData)
        #expect(sendedShowAudioData!.type == .update)
        #expect(sendedShowAudioData!.subType == .audioList)
        await #expect(rootSut.gameModel.gameConfig.master == gameConfigModelSut.master)
        await #expect(rootSut.gameModel.gameConfig.players == [gameConfigModelPlayer.players[0], gameConfigModel3Player.players[0], gameConfigModel2Player.players[0]])
        await #expect(rootSut.gameModel.gameConfig.controls == [
            SharingControlModel(id: gameConfigModelPlayer.id, name: gameConfigModelPlayer.name, show: true),
            SharingControlModel(id: gameConfigModel3Player.id, name: gameConfigModel3Player.name, show: true),
            SharingControlModel(id: gameConfigModel2Player.id, name: gameConfigModel2Player.name, show: true)
        ])
        await #expect(rootSut.audioRoot.itemController.itemOrEmpty(for: audioId).players.sorted() == [gameConfigModel3Player.id, gameConfigModelSut.id].sorted())
        var reportResult = await rootSut.audioRoot.gameController.allPlayersReported(for: audioId)
        #expect(reportResult == false)
        
        // apply audiolist
        playerStoreAbstractionMock.requestData = nil
        await sut3Player.receivedProcess(sendedShowAudioData!)
        respondedShowAudioData3 = playerStoreAbstractionMock.requestData as? GameNetworkModel
        #expect(nil == respondedShowAudioData3)
        await #expect(root3Player.audioRoot.itemController.itemOrEmpty(for: audioId).players.sorted() == [gameConfigModel3Player.id, gameConfigModelSut.id].sorted())
        reportResult = await root3Player.audioRoot.gameController.allPlayersReported(for: audioId)
        #expect(reportResult == false)
        
        //status code other players
        await sut.receivedProcess(respondedShowAudioData2!, connectionId: nil)
        sendedShowAudioData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(nil != sendedShowAudioData)
        await #expect(rootSut.gameModel.gameConfig.master == gameConfigModelSut.master)
        await #expect(rootSut.gameModel.gameConfig.players == [gameConfigModelPlayer.players[0], gameConfigModel3Player.players[0], gameConfigModel2Player.players[0]])
        await #expect(rootSut.gameModel.gameConfig.controls == [
            SharingControlModel(id: gameConfigModelPlayer.id, name: gameConfigModelPlayer.name, show: true),
            SharingControlModel(id: gameConfigModel3Player.id, name: gameConfigModel3Player.name, show: true),
            SharingControlModel(id: gameConfigModel2Player.id, name: gameConfigModel2Player.name, show: true)
        ])
        await #expect(rootSut.audioRoot.itemController.itemOrEmpty(for: audioId).players.sorted() == [gameConfigModel2Player.id, gameConfigModel3Player.id, gameConfigModelSut.id].sorted())
        await #expect(rootSut.audioRoot.gameController.allPlayersReported(for: audioId) == false)
        
        await sut.receivedProcess(respondedShowAudioData1!, connectionId: nil)
        sendedShowAudioData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(nil != sendedShowAudioData)
        await #expect(rootSut.gameModel.gameConfig.master == gameConfigModelSut.master)
        await #expect(rootSut.gameModel.gameConfig.players == [gameConfigModelPlayer.players[0], gameConfigModel3Player.players[0], gameConfigModel2Player.players[0]])
        await #expect(rootSut.gameModel.gameConfig.controls == [
            SharingControlModel(id: gameConfigModelPlayer.id, name: gameConfigModelPlayer.name, show: true),
            SharingControlModel(id: gameConfigModel3Player.id, name: gameConfigModel3Player.name, show: true),
            SharingControlModel(id: gameConfigModel2Player.id, name: gameConfigModel2Player.name, show: true)
        ])
        await #expect(rootSut.audioRoot.itemController.itemOrEmpty(for: audioId).players.sorted() == [gameConfigModelPlayer.id, gameConfigModel2Player.id, gameConfigModel3Player.id, gameConfigModelSut.id].sorted())
        reportResult = await rootSut.audioRoot.gameController.allPlayersReported(for: audioId)
        #expect(reportResult)
        
        // now play
        let playData = await rootSut.audioRoot.gameController.requestPlay(id: audioId)
        await sut.game(message: playData, actionType: .playAudio)
        let sendedPlayAudioData = masterStoreAbstractionMock.sendResponseData as? GameNetworkModel
        #expect(nil != sendedPlayAudioData)
        
        playerStoreAbstractionMock.requestData = nil
        
        // Player receive Play
        await sutPlayer.receivedProcess(sendedPlayAudioData!)
        var respondedPlayAudioData = playerStoreAbstractionMock.requestData as? GameNetworkModel
        #expect(nil == respondedPlayAudioData)
        await #expect(rootPlayer.audioRoot.audioController.model.playList.count == 1)
        await #expect(rootPlayer.audioRoot.audioController.model.playList[0].id == audioId)
        await #expect(rootPlayer.audioRoot.audioController.model.currentId == audioId)
        await #expect(rootPlayer.audioRoot.itemController.itemOrEmpty(for: audioId).players.sorted() == [gameConfigModelPlayer.id, gameConfigModel2Player.id, gameConfigModel3Player.id, gameConfigModelSut.id].sorted())
        reportResult = await rootPlayer.audioRoot.gameController.allPlayersReported(for: audioId)
        #expect(reportResult)

        await sut2Player.receivedProcess(sendedPlayAudioData!)
        respondedPlayAudioData = playerStoreAbstractionMock.requestData as? GameNetworkModel
        #expect(nil == respondedPlayAudioData)
        await #expect(root2Player.audioRoot.audioController.model.playList.count == 1)
        await #expect(root2Player.audioRoot.audioController.model.playList[0].id == audioId)
        await #expect(root2Player.audioRoot.audioController.model.currentId == audioId)
        await #expect(root2Player.audioRoot.itemController.itemOrEmpty(for: audioId).players.sorted() == [gameConfigModelPlayer.id, gameConfigModel2Player.id, gameConfigModel3Player.id, gameConfigModelSut.id].sorted())
        reportResult = await root2Player.audioRoot.gameController.allPlayersReported(for: audioId)
        #expect(reportResult)

        await sut3Player.receivedProcess(sendedPlayAudioData!)
        respondedPlayAudioData = playerStoreAbstractionMock.requestData as? GameNetworkModel
        #expect(nil == respondedPlayAudioData)
        await #expect(root3Player.audioRoot.audioController.model.playList.count == 1)
        await #expect(root3Player.audioRoot.audioController.model.playList[0].id == audioId)
        await #expect(root3Player.audioRoot.audioController.model.currentId == audioId)
        await #expect(root3Player.audioRoot.itemController.itemOrEmpty(for: audioId).players.sorted() == [gameConfigModelPlayer.id, gameConfigModel2Player.id, gameConfigModel3Player.id, gameConfigModelSut.id].sorted())

        reportResult = await root3Player.audioRoot.gameController.allPlayersReported(for: audioId)
        #expect(reportResult)
    }
}
#endif

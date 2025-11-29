// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Network
import Testing

@testable import GameRPG

final class NetworkStoreTests {
    private var masterDeleagteMock: MasterNetworkStoreDelegateMock!
    private var playerDelegateMock: PlayerNetworkStoreDelegateMock!
    private var masterStoreAbstractionMock: MasterNetworkControllableMock!
    private var playerStoreAbstractionMock: PlayerStoreAbstractionMock!

    private var sut: NetworkController!

    func setUp() async throws {
        masterDeleagteMock = MasterNetworkStoreDelegateMock()
        playerDelegateMock = PlayerNetworkStoreDelegateMock()
        let masterMock = await MasterNetworkControllableMock()
        let playerMock = await PlayerStoreAbstractionMock()

        sut = await NetworkController(name: "Hello Test", masterBuilder: { _, _ in
            masterMock
        }, playerBuilder: { _, _ in
            playerMock
        })
        await sut.model.setMaster(delegate: masterDeleagteMock)
        await sut.model.setPlayer(delegate: playerDelegateMock)
        masterStoreAbstractionMock = masterMock
        playerStoreAbstractionMock = playerMock
    }

    @Test func MasterGame() async throws {
        try await setUp()
        await sut.startMasterGame(game: .master, titleImage: nil)
        #expect(masterStoreAbstractionMock.calledStartStreaming == 1)

        await sut.masterReady(for: ConnectionController.ID())
        #expect(masterDeleagteMock.calledReady == 1)

        await sut.sendPlayer(masterGameNetworkModel, to: ConnectionController.ID())
        #expect(masterStoreAbstractionMock.calledSendResponseId == 1)

        await sut.sendPlayer(data: masterGameNetworkModel, fileJournal: false)
        #expect(masterStoreAbstractionMock.calledSendResponseAll == 1)

        await sut.masterReceived(data: masterGameNetworkModel.encodeData(), for: ConnectionController.ID(), fileJournal: false)
        #expect(masterStoreAbstractionMock.calledSendResponseExcept == 1)
        #expect(masterDeleagteMock.calledReceived == 1)

        await sut.stopGame()
        #expect(masterStoreAbstractionMock.calledStopStreaming == 0)
        await masterStoreAbstractionMock.networkModel.reset(isStreaming: true)
        await sut.stopGame()
        #expect(masterStoreAbstractionMock.calledStopStreaming == 1)
    }

    @Test func PlayerGame() async throws {
        try await setUp()
        let result = await sut.startPlayerGame(to: nil)
        #expect(result == false)
        #expect(playerStoreAbstractionMock.calledToggleConnection == 0)

        let connectResult = await sut.startPlayerGame(to: BrowserDeviceModel(id: UUID(), deviceName: "MasterTestDevice"))
        #expect(connectResult)
        #expect(playerStoreAbstractionMock.calledToggleConnection == 1)

        await sut.playerReady()
        #expect(playerDelegateMock.calledReady == 1)

        await sut.sendMaster(data: playerGameNetworkModel, fileJournal: false)
        #expect(playerStoreAbstractionMock.calledRequest == 1)

        await sut.playerReceived(data: playerGameNetworkModel.encodeData())
        #expect(playerDelegateMock.calledReceived == 1)

        await sut.playerLostMaster()
        #expect(playerDelegateMock.calledLostConnection == 1)

        await sut.stopGame()
        #expect(playerStoreAbstractionMock.calledStop == 1)
    }

    private var masterGameNetworkModel = GameNetworkModel(counter: 1, proxyCounter: 0, type: .reveal, subType: .show, gameConfig: .master, data: NetworkCodableDataType(id: UUID(), type: .none, version: 0, data: nil))

    private var playerGameNetworkModel = GameNetworkModel(counter: 2, proxyCounter: 0, type: .reveal, subType: .show, gameConfig: .player, data: NetworkCodableDataType(id: UUID(), type: .none, version: 0, data: nil))
}
#endif

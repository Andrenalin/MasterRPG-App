// @copyright André Trettin

#if canImport(Testing)
import AndrenalinKit
import Foundation
import Network
import Testing

@testable import GameRPG

final class MasterNetworkControllerTests {

    @Test func startStreaming() async throws {
        let delegateMock = MasterNetworkControllerDelegateMock()
        let listnerMock = GameListnerAbstractionMock()

        let sut = await MasterNetworkController(name: "TestMasterTest", delegate: delegateMock, listnerBuilder: { _, _, _ in
            listnerMock
        })

        await sut.startStreaming()

        await #expect(sut.networkModel.name == "TestMasterTest")
        var isStreaming = await sut.networkModel.isStreaming
        #expect(isStreaming)
        await #expect(sut.networkModel.connections.isEmpty)

        #expect(listnerMock.calledStartListening == 1)
        await #expect(sut.networkModel.browserController?.isBrowsing ?? false)

        await sut.toggleStreaming()
        isStreaming = await sut.networkModel.isStreaming
        #expect(!isStreaming)
        await #expect(sut.networkModel.connections.isEmpty)
        await #expect((sut.networkModel.browserController?.isBrowsing ?? false) == false)

        await sut.toggleStreaming()
        isStreaming = await sut.networkModel.isStreaming
        #expect(isStreaming)
        await #expect(sut.networkModel.connections.isEmpty)
        #expect(listnerMock.calledStartListening == 2)
        await #expect(sut.networkModel.browserController?.isBrowsing ?? false)

        await sut.newConnection(for: NWConnection(host: .init("http://localhost"), port: .any, using: .tcp))
        await #expect(sut.networkModel.connections.count == 1)

        let connectionId = await sut.networkModel.connections.first!.id
        await sut.readyConnection(for: connectionId)
        #expect(delegateMock.calledReady == 1)

        await sut.received(data: nil, for: connectionId)
        #expect(delegateMock.calledReceived == 1)

        await sut.sendResponse(data: nil)
        await sut.sendResponse(data: nil, id: UUID())
        await sut.sendResponse(data: nil, except: UUID())
        await sut.sendResponse(data: nil, except: connectionId)

        await sut.lostConnection(for: UUID())
        await #expect(sut.networkModel.connections.count == 1)
        #expect(delegateMock.calledLostPlayer == 0)

        await sut.failed(with: "Error", for: UUID())
        await #expect(sut.networkModel.connections.count == 1)
        #expect(delegateMock.calledLostPlayer == 0)

        await sut.failed(with: "Error", for: connectionId)
        await #expect(sut.networkModel.connections.isEmpty)
        #expect(delegateMock.calledLostPlayer == 1)

        await sut.cancelled()
        // fix later after GameListner
        isStreaming = await sut.networkModel.isStreaming
        #expect(!isStreaming)

        await #expect(sut.networkModel.connections.isEmpty)
    }
}
#endif

// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Network
import Testing

@testable import GameRPG

/// Test environment for MasterNetworkController tests.
@MainActor
struct MasterNetworkControllerTestEnvironment {
    let controller: MasterNetworkController
    let delegateSpy: MasterNetworkControllerDelegateMock
    let listenerSpy: GameListnerAbstractionMock

    /// Creates a MasterNetworkController with test dependencies
    static func create(name: String = "TestMasterTest") async -> MasterNetworkControllerTestEnvironment {
        let delegateSpy = MasterNetworkControllerDelegateMock()
        let listenerSpy = GameListnerAbstractionMock()

        let controller = MasterNetworkController(
            name: name,
            delegate: delegateSpy,
            listnerBuilder: { _, _, _ in listenerSpy as any ListenerManaging }
        )

        return MasterNetworkControllerTestEnvironment(
            controller: controller,
            delegateSpy: delegateSpy,
            listenerSpy: listenerSpy
        )
    }
}

/// Access to the count is serialized by `lock`, making the test mapper safe to
/// call from any task used by the controller.
private final class MessageEncodingCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func increment() {
        lock.lock()
        storedValue += 1
        lock.unlock()
    }
}

private struct MessageMapperEncodingSpy: MessageMapper {
    let encodedData: Data
    let counter: MessageEncodingCounter

    func encodeData() -> Data? {
        counter.increment()
        return encodedData
    }

    static func decodeData(of data: Data?) -> MessageMapperEncodingSpy? {
        nil
    }
}

@Suite("Master network controller tests")
@MainActor
struct MasterNetworkControllerTests {

    @Test("Start streaming enables listener and browser")
    func startStreaming() async throws {
        // Arrange
        let env = await MasterNetworkControllerTestEnvironment.create()

        // Act
        env.controller.startStreaming()

        // Assert
        #expect(env.controller.networkModel.name == "TestMasterTest")
        let isStreaming = env.controller.networkModel.isStreaming
        #expect(isStreaming)
        #expect(env.controller.networkModel.connections.isEmpty)
        #expect(env.listenerSpy.calledStartListening == 1)
        #expect(env.controller.networkModel.browserManager?.isBrowsing ?? false)
    }

    @Test("Toggle streaming stops and restarts services")
    func toggleStreaming() async throws {
        // Arrange
        let env = await MasterNetworkControllerTestEnvironment.create()
        env.controller.startStreaming()

        // Act - Toggle off
        env.controller.toggleStreaming()

        // Assert - Streaming stopped
        var isStreaming = env.controller.networkModel.isStreaming
        #expect(!isStreaming)
        #expect(env.controller.networkModel.connections.isEmpty)
        #expect((env.controller.networkModel.browserManager?.isBrowsing ?? false) == false)

        // Act - Toggle back on
        env.controller.toggleStreaming()

        // Assert - Streaming restarted
        isStreaming = env.controller.networkModel.isStreaming
        #expect(isStreaming)
        #expect(env.controller.networkModel.connections.isEmpty)
        #expect(env.listenerSpy.calledStartListening == 2)
        #expect(env.controller.networkModel.browserManager?.isBrowsing ?? false)
    }

    @Test("New connection adds to connections list")
    func newConnection() async throws {
        // Arrange
        let env = await MasterNetworkControllerTestEnvironment.create()
        env.controller.startStreaming()

        // Act
        await env.controller.newConnection(for: NWConnection(host: .init("http://localhost"), port: .any, using: .tcp))

        // Assert
        #expect(env.controller.networkModel.connections.count == 1)
    }

    @Test("Ready connection triggers delegate callback")
    func readyConnection() async throws {
        // Arrange
        let env = await MasterNetworkControllerTestEnvironment.create()
        env.controller.startStreaming()
        await env.controller.newConnection(for: NWConnection(host: .init("http://localhost"), port: .any, using: .tcp))
        let connectionId = env.controller.networkModel.connections.first!.id

        // Act
        await env.controller.readyConnection(for: connectionId)

        // Assert
        #expect(env.delegateSpy.calledReady == 1)
    }

    @Test("Received data triggers delegate callback")
    func receivedData() async throws {
        // Arrange
        let env = await MasterNetworkControllerTestEnvironment.create()
        env.controller.startStreaming()
        await env.controller.newConnection(for: NWConnection(host: .init("http://localhost"), port: .any, using: .tcp))
        let connectionId = env.controller.networkModel.connections.first!.id

        // Act
        await env.controller.received(data: nil, for: connectionId)

        // Assert
        #expect(env.delegateSpy.calledReceived == 1)
    }

    @Test("Send response methods work for all targets")
    func sendResponse() async throws {
        // Arrange
        let env = await MasterNetworkControllerTestEnvironment.create()
        env.controller.startStreaming()
        await env.controller.newConnection(for: NWConnection(host: .init("http://localhost"), port: .any, using: .tcp))
        let connectionId = env.controller.networkModel.connections.first!.id

        // Act & Assert - All send methods execute without error
        await env.controller.sendResponse(data: nil)
        let deliveredToUnknown = await env.controller.sendResponse(data: nil, id: UUID())
        #expect(!deliveredToUnknown)
        let deliveredToConnection = await env.controller.sendResponse(data: nil, id: connectionId)
        #expect(deliveredToConnection)
        await env.controller.sendResponse(data: nil, except: UUID())
        await env.controller.sendResponse(data: nil, except: connectionId)
    }

    @Test("Broadcast encodes once and reuses the payload for every connection")
    func broadcastEncodesOnce() async {
        // Arrange
        let env = await MasterNetworkControllerTestEnvironment.create()
        let firstConnection = ConnectionControllableSpyingStub()
        let secondConnection = ConnectionControllableSpyingStub()
        env.controller.networkModel.connections = [firstConnection, secondConnection]
        let counter = MessageEncodingCounter()
        let expectedData = Data([0x01, 0x02, 0x03])
        let mapper = MessageMapperEncodingSpy(encodedData: expectedData, counter: counter)

        // Act
        await env.controller.sendResponse(data: mapper)

        // Assert
        let firstContents = await firstConnection.responseEncodedContents
        let secondContents = await secondConnection.responseEncodedContents
        #expect(counter.value == 1)
        #expect(firstContents.count == 1)
        #expect(secondContents.count == 1)
        #expect(firstContents.compactMap { $0 } == [expectedData])
        #expect(secondContents.compactMap { $0 } == [expectedData])
        #expect(await firstConnection.responseTypes == [.gameData])
        #expect(await secondConnection.responseTypes == [.gameData])
    }

    @Test("Broadcast excluding a connection still encodes only once")
    func broadcastExceptEncodesOnce() async {
        // Arrange
        let includedConnection = ConnectionControllableSpyingStub()
        let excludedConnection = ConnectionControllableSpyingStub()
        let otherIncludedConnection = ConnectionControllableSpyingStub()
        let env = await MasterNetworkControllerTestEnvironment.create()
        env.controller.networkModel.connections = [
            includedConnection,
            excludedConnection,
            otherIncludedConnection
        ]
        let counter = MessageEncodingCounter()
        let expectedData = Data([0x04, 0x05, 0x06])
        let mapper = MessageMapperEncodingSpy(encodedData: expectedData, counter: counter)

        // Act
        await env.controller.sendResponse(data: mapper, except: excludedConnection.id)

        // Assert
        #expect(counter.value == 1)
        #expect(await includedConnection.responseEncodedContents.count == 1)
        #expect(await excludedConnection.responseEncodedContents.isEmpty)
        #expect(await otherIncludedConnection.responseEncodedContents.count == 1)
    }

    @Test("Targeted response encodes only after finding the exact connection")
    func targetedResponsePreservesExactDelivery() async {
        // Arrange
        let targetConnection = ConnectionControllableSpyingStub()
        let otherConnection = ConnectionControllableSpyingStub()
        let env = await MasterNetworkControllerTestEnvironment.create()
        env.controller.networkModel.connections = [targetConnection, otherConnection]
        let counter = MessageEncodingCounter()
        let mapper = MessageMapperEncodingSpy(encodedData: Data([0x07]), counter: counter)

        // Act
        let unknownDelivered = await env.controller.sendResponse(data: mapper, id: UUID())
        let targetDelivered = await env.controller.sendResponse(data: mapper, id: targetConnection.id)

        // Assert
        #expect(!unknownDelivered)
        #expect(targetDelivered)
        #expect(counter.value == 1)
        #expect(await targetConnection.responseEncodedContents.count == 1)
        #expect(await otherConnection.responseEncodedContents.isEmpty)
    }

    @Test("Broadcast does not encode when no connection can receive it")
    func broadcastWithoutRecipientDoesNotEncode() async {
        // Arrange
        let onlyConnection = ConnectionControllableSpyingStub()
        let env = await MasterNetworkControllerTestEnvironment.create()
        env.controller.networkModel.connections = [onlyConnection]
        let counter = MessageEncodingCounter()
        let mapper = MessageMapperEncodingSpy(encodedData: Data([0x08]), counter: counter)

        // Act
        await env.controller.sendResponse(data: mapper, except: onlyConnection.id)

        // Assert
        #expect(counter.value == 0)
        #expect(await onlyConnection.responseEncodedContents.isEmpty)
    }

    @Test("Lost connection with unknown ID does not trigger delegate")
    func lostConnectionUnknownId() async throws {
        // Arrange
        let env = await MasterNetworkControllerTestEnvironment.create()
        env.controller.startStreaming()
        await env.controller.newConnection(for: NWConnection(host: .init("http://localhost"), port: .any, using: .tcp))

        // Act
        await env.controller.lostConnection(for: UUID())

        // Assert
        #expect(env.controller.networkModel.connections.count == 1)
        #expect(env.delegateSpy.calledLostPlayer == 0)
    }

    @Test("Failed connection with unknown ID does not trigger delegate")
    func failedConnectionUnknownId() async throws {
        // Arrange
        let env = await MasterNetworkControllerTestEnvironment.create()
        env.controller.startStreaming()
        await env.controller.newConnection(for: NWConnection(host: .init("http://localhost"), port: .any, using: .tcp))

        // Act
        await env.controller.failed(with: "Error", for: UUID())

        // Assert
        #expect(env.controller.networkModel.connections.count == 1)
        #expect(env.delegateSpy.calledLostPlayer == 0)
    }

    @Test("Failed connection with valid ID removes connection and triggers delegate")
    func failedConnectionValidId() async throws {
        // Arrange
        let env = await MasterNetworkControllerTestEnvironment.create()
        env.controller.startStreaming()
        await env.controller.newConnection(for: NWConnection(host: .init("http://localhost"), port: .any, using: .tcp))
        let connectionId = env.controller.networkModel.connections.first!.id

        // Act
        await env.controller.failed(with: "Error", for: connectionId)

        // Assert
        #expect(env.controller.networkModel.connections.isEmpty)
        #expect(env.delegateSpy.calledLostPlayer == 1)
    }

    @Test("Cancelled stops streaming")
    func cancelled() async throws {
        // Arrange
        let env = await MasterNetworkControllerTestEnvironment.create()
        env.controller.startStreaming()

        // Act
        await env.controller.listenerCancelled()

        // Assert
        let isStreaming = env.controller.networkModel.isStreaming
        #expect(!isStreaming)
        #expect(env.controller.networkModel.connections.isEmpty)
    }
}

@Suite("Player join options tests")
struct PlayerJoinOptionsTests {
    @Test("SharePlay availability does not hide the local network option")
    func sharePlayAndLocalNetworkAreBothAvailable() {
        // Arrange and act
        let options = PlayerJoinOptions(canActivateSharePlay: true, hasLocalNetwork: true)

        // Assert
        #expect(options.availableTransports == [.sharePlay, .localNetwork])
    }

    @Test("Local network remains available without SharePlay")
    func localNetworkIsAvailableWithoutSharePlay() {
        // Arrange and act
        let options = PlayerJoinOptions(canActivateSharePlay: false, hasLocalNetwork: true)

        // Assert
        #expect(options.availableTransports == [.localNetwork])
    }
}
#endif

// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Network
import Testing

@testable import GameRPG

/// Test environment for MasterNetworkController tests.
struct MasterNetworkControllerTestEnvironment {
    let controller: MasterNetworkController
    let delegateSpy: MasterNetworkControllerDelegateMock
    let listenerSpy: GameListnerAbstractionMock

    /// Creates a MasterNetworkController with test dependencies
    static func create(name: String = "TestMasterTest") async -> MasterNetworkControllerTestEnvironment {
        let delegateSpy = MasterNetworkControllerDelegateMock()
        let listenerSpy = GameListnerAbstractionMock()

        let controller = await MasterNetworkController(
            name: name,
            delegate: delegateSpy,
            listnerBuilder: { _, _, _ in listenerSpy }
        )

        return MasterNetworkControllerTestEnvironment(
            controller: controller,
            delegateSpy: delegateSpy,
            listenerSpy: listenerSpy
        )
    }
}

@Suite("Master network controller tests")
struct MasterNetworkControllerTests {

    @Test("Start streaming enables listener and browser")
    func startStreaming() async throws {
        // Arrange
        let env = await MasterNetworkControllerTestEnvironment.create()

        // Act
        await env.controller.startStreaming()

        // Assert
        await #expect(env.controller.networkModel.name == "TestMasterTest")
        let isStreaming = await env.controller.networkModel.isStreaming
        #expect(isStreaming)
        await #expect(env.controller.networkModel.connections.isEmpty)
        #expect(env.listenerSpy.calledStartListening == 1)
        await #expect(env.controller.networkModel.browserManager?.isBrowsing ?? false)
    }

    @Test("Toggle streaming stops and restarts services")
    func toggleStreaming() async throws {
        // Arrange
        let env = await MasterNetworkControllerTestEnvironment.create()
        await env.controller.startStreaming()

        // Act - Toggle off
        await env.controller.toggleStreaming()

        // Assert - Streaming stopped
        var isStreaming = await env.controller.networkModel.isStreaming
        #expect(!isStreaming)
        await #expect(env.controller.networkModel.connections.isEmpty)
        await #expect((env.controller.networkModel.browserManager?.isBrowsing ?? false) == false)

        // Act - Toggle back on
        await env.controller.toggleStreaming()

        // Assert - Streaming restarted
        isStreaming = await env.controller.networkModel.isStreaming
        #expect(isStreaming)
        await #expect(env.controller.networkModel.connections.isEmpty)
        #expect(env.listenerSpy.calledStartListening == 2)
        await #expect(env.controller.networkModel.browserManager?.isBrowsing ?? false)
    }

    @Test("New connection adds to connections list")
    func newConnection() async throws {
        // Arrange
        let env = await MasterNetworkControllerTestEnvironment.create()
        await env.controller.startStreaming()

        // Act
        await env.controller.newConnection(for: NWConnection(host: .init("http://localhost"), port: .any, using: .tcp))

        // Assert
        await #expect(env.controller.networkModel.connections.count == 1)
    }

    @Test("Ready connection triggers delegate callback")
    func readyConnection() async throws {
        // Arrange
        let env = await MasterNetworkControllerTestEnvironment.create()
        await env.controller.startStreaming()
        await env.controller.newConnection(for: NWConnection(host: .init("http://localhost"), port: .any, using: .tcp))
        let connectionId = await env.controller.networkModel.connections.first!.id

        // Act
        await env.controller.readyConnection(for: connectionId)

        // Assert
        #expect(env.delegateSpy.calledReady == 1)
    }

    @Test("Received data triggers delegate callback")
    func receivedData() async throws {
        // Arrange
        let env = await MasterNetworkControllerTestEnvironment.create()
        await env.controller.startStreaming()
        await env.controller.newConnection(for: NWConnection(host: .init("http://localhost"), port: .any, using: .tcp))
        let connectionId = await env.controller.networkModel.connections.first!.id

        // Act
        await env.controller.received(data: nil, for: connectionId)

        // Assert
        #expect(env.delegateSpy.calledReceived == 1)
    }

    @Test("Send response methods work for all targets")
    func sendResponse() async throws {
        // Arrange
        let env = await MasterNetworkControllerTestEnvironment.create()
        await env.controller.startStreaming()
        await env.controller.newConnection(for: NWConnection(host: .init("http://localhost"), port: .any, using: .tcp))
        let connectionId = await env.controller.networkModel.connections.first!.id

        // Act & Assert - All send methods execute without error
        await env.controller.sendResponse(data: nil)
        await env.controller.sendResponse(data: nil, id: UUID())
        await env.controller.sendResponse(data: nil, except: UUID())
        await env.controller.sendResponse(data: nil, except: connectionId)
    }

    @Test("Lost connection with unknown ID does not trigger delegate")
    func lostConnectionUnknownId() async throws {
        // Arrange
        let env = await MasterNetworkControllerTestEnvironment.create()
        await env.controller.startStreaming()
        await env.controller.newConnection(for: NWConnection(host: .init("http://localhost"), port: .any, using: .tcp))

        // Act
        await env.controller.lostConnection(for: UUID())

        // Assert
        await #expect(env.controller.networkModel.connections.count == 1)
        #expect(env.delegateSpy.calledLostPlayer == 0)
    }

    @Test("Failed connection with unknown ID does not trigger delegate")
    func failedConnectionUnknownId() async throws {
        // Arrange
        let env = await MasterNetworkControllerTestEnvironment.create()
        await env.controller.startStreaming()
        await env.controller.newConnection(for: NWConnection(host: .init("http://localhost"), port: .any, using: .tcp))

        // Act
        await env.controller.failed(with: "Error", for: UUID())

        // Assert
        await #expect(env.controller.networkModel.connections.count == 1)
        #expect(env.delegateSpy.calledLostPlayer == 0)
    }

    @Test("Failed connection with valid ID removes connection and triggers delegate")
    func failedConnectionValidId() async throws {
        // Arrange
        let env = await MasterNetworkControllerTestEnvironment.create()
        await env.controller.startStreaming()
        await env.controller.newConnection(for: NWConnection(host: .init("http://localhost"), port: .any, using: .tcp))
        let connectionId = await env.controller.networkModel.connections.first!.id

        // Act
        await env.controller.failed(with: "Error", for: connectionId)

        // Assert
        await #expect(env.controller.networkModel.connections.isEmpty)
        #expect(env.delegateSpy.calledLostPlayer == 1)
    }

    @Test("Cancelled stops streaming")
    func cancelled() async throws {
        // Arrange
        let env = await MasterNetworkControllerTestEnvironment.create()
        await env.controller.startStreaming()

        // Act
        await env.controller.cancelled()

        // Assert
        let isStreaming = await env.controller.networkModel.isStreaming
        #expect(!isStreaming)
        await #expect(env.controller.networkModel.connections.isEmpty)
    }
}
#endif

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
    let listenerSpy: GameListenerAbstractionMock

    /// Creates a MasterNetworkController with test dependencies
    static func create(
        name: String = "TestMasterTest",
        browserConnectionBuilder: @MainActor @Sendable @escaping (NWEndpoint, String, any ConnectionControllerDelegate) -> any ConnectionControllable = MasterNetworkController.gameBrowserConnectionBuilder()
    ) async -> MasterNetworkControllerTestEnvironment {
        let delegateSpy = MasterNetworkControllerDelegateMock()
        let listenerSpy = GameListenerAbstractionMock()

        let controller = MasterNetworkController(
            name: name,
            delegate: delegateSpy,
            listenerBuilder: { _, _, _, _, _, _ in listenerSpy as any ListenerManaging },
            browserConnectionBuilder: browserConnectionBuilder,
            hostingSessions: HostingSessionStore(storage: InMemoryJoinCodeStorage())
        )

        return MasterNetworkControllerTestEnvironment(
            controller: controller,
            delegateSpy: delegateSpy,
            listenerSpy: listenerSpy
        )
    }
}

@MainActor
private final class BrowserConnectionFactorySpy {
    private(set) var endpoints: [NWEndpoint] = []
    private(set) var connections: [ConnectionControllableSpyingStub] = []

    func makeConnection(endpoint: NWEndpoint) -> any ConnectionControllable {
        let connection = ConnectionControllableSpyingStub()
        endpoints.append(endpoint)
        connections.append(connection)
        return connection
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
        env.controller.startStreaming(passcode: "1234")

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
        env.controller.startStreaming(passcode: "1234")

        // Act - Toggle off
        env.controller.toggleStreaming(passcode: "1234")

        // Assert - Streaming stopped
        var isStreaming = env.controller.networkModel.isStreaming
        #expect(!isStreaming)
        #expect(env.controller.networkModel.connections.isEmpty)
        #expect((env.controller.networkModel.browserManager?.isBrowsing ?? false) == false)

        // Act - Toggle back on
        env.controller.toggleStreaming(passcode: "1234")

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
        env.controller.startStreaming(passcode: "1234")

        // Act
        await env.controller.newConnection(for: .game(to: .hostPort(host: "localhost", port: .any), passcode: "1234"))

        // Assert
        #expect(env.controller.networkModel.connections.count == 1)
    }

    @Test("Ready connection triggers delegate callback")
    func readyConnection() async throws {
        // Arrange
        let env = await MasterNetworkControllerTestEnvironment.create()
        env.controller.startStreaming(passcode: "1234")
        await env.controller.newConnection(for: .game(to: .hostPort(host: "localhost", port: .any), passcode: "1234"))
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
        env.controller.startStreaming(passcode: "1234")
        await env.controller.newConnection(for: .game(to: .hostPort(host: "localhost", port: .any), passcode: "1234"))
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
        env.controller.startStreaming(passcode: "1234")
        await env.controller.newConnection(for: .game(to: .hostPort(host: "localhost", port: .any), passcode: "1234"))
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
        env.controller.startStreaming(passcode: "1234")
        await env.controller.newConnection(for: .game(to: .hostPort(host: "localhost", port: .any), passcode: "1234"))

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
        env.controller.startStreaming(passcode: "1234")
        await env.controller.newConnection(for: .game(to: .hostPort(host: "localhost", port: .any), passcode: "1234"))

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
        env.controller.startStreaming(passcode: "1234")
        await env.controller.newConnection(for: .game(to: .hostPort(host: "localhost", port: .any), passcode: "1234"))
        let connectionId = env.controller.networkModel.connections.first!.id

        // Act
        await env.controller.failed(with: "Error", for: connectionId)

        // Assert
        #expect(env.controller.networkModel.connections.isEmpty)
        #expect(env.delegateSpy.calledLostPlayer == 1)
    }

    @Test("Failed fallback connection releases endpoint for another reconnect")
    func failedFallbackConnectionAllowsReconnect() async throws {
        // Arrange
        let factory = BrowserConnectionFactorySpy()
        let env = await MasterNetworkControllerTestEnvironment.create(
            browserConnectionBuilder: { endpoint, _, _ in
                factory.makeConnection(endpoint: endpoint)
            }
        )
        let endpoint = NWEndpoint.service(
            name: "FallbackPlayer",
            type: GameServiceType.master.serviceName,
            domain: "local.",
            interface: nil
        )
        env.controller.connectToPlayer(endpoint: endpoint)
        let firstConnection = try #require(factory.connections.first)

        // Act
        await env.controller.failed(with: "Connection failed", for: firstConnection.id)
        env.controller.connectToPlayer(endpoint: endpoint)

        // Assert
        #expect(factory.endpoints == [endpoint, endpoint])
        #expect(env.controller.networkModel.browserConnections == [endpoint])
        #expect(env.controller.networkModel.connections.count == 1)
        #expect(env.delegateSpy.calledLostPlayer == 1)
    }

    @Test("Removed fallback service releases endpoint for a later reconnect")
    func removedFallbackServiceAllowsReconnect() async {
        // Arrange
        let factory = BrowserConnectionFactorySpy()
        let env = await MasterNetworkControllerTestEnvironment.create(
            browserConnectionBuilder: { endpoint, _, _ in
                factory.makeConnection(endpoint: endpoint)
            }
        )
        env.controller.startProxyStreaming(passcode: "1234")
        let game = BrowserGameModel(
            id: UUID(),
            endpointName: "FallbackPlayer",
            connectionMode: .proxy,
            sessionId: env.controller.networkModel.sessionId
        )

        // Act
        env.controller.refresh(games: [game])
        env.controller.refresh(games: [])
        env.controller.refresh(games: [game])

        // Assert
        #expect(factory.endpoints.count == 2)
        #expect(factory.endpoints.first == factory.endpoints.last)
        #expect(env.controller.networkModel.browserConnections.count == 1)
        #expect(env.controller.networkModel.connections.count == 2)
        env.controller.stopStreaming()
    }

    @Test("A failed listener keeps hosting, keeps players and is recreated")
    func cancelledRestartsListener() async throws {
        // Arrange
        let env = await MasterNetworkControllerTestEnvironment.create()
        env.controller.startStreaming(passcode: "1234")
        await env.controller.newConnection(for: .game(to: .hostPort(host: "localhost", port: .any), passcode: "1234"))

        // Act
        await env.controller.listenerCancelled()

        // Assert: hosting continues, the player stays, the listener is scheduled to restart
        #expect(env.controller.networkModel.isStreaming)
        #expect(env.controller.networkModel.connections.count == 1)
        #expect(env.controller.networkModel.listener == nil)
        #expect(env.controller.networkModel.listenerStatus == .restarting)
        #expect(env.listenerSpy.calledStopListening == 1)

        // The listener comes back after the first restart pause; it reads as restarting
        // until the new listener reports `.ready` (CODE_AUDIT_17 §5.22, CODE_AUDIT_18 §5.15).
        #expect(await waitUntil(timeout: .seconds(5)) { env.listenerSpy.calledStartListening == 2 })
        #expect(env.controller.networkModel.listenerStatus == .restarting)
        await env.controller.listenerReady()
        #expect(env.controller.networkModel.listenerStatus == .running)
        env.controller.stopStreaming()
    }

    @Test("Listener failure after streaming stopped does nothing")
    func cancelledAfterStopIsIgnored() async {
        // Arrange
        let env = await MasterNetworkControllerTestEnvironment.create()
        env.controller.startStreaming(passcode: "1234")
        env.controller.stopStreaming()

        // Act
        await env.controller.listenerCancelled()

        // Assert
        #expect(!env.controller.networkModel.isStreaming)
        #expect(env.controller.networkModel.listenerStatus == .stopped)
    }

    @Test("A waiting listener shows as waiting, not stopped")
    func waitingListenerStatus() async {
        // Arrange
        let env = await MasterNetworkControllerTestEnvironment.create()
        env.controller.startStreaming(passcode: "1234")

        // Act
        await env.controller.listenerWaiting(.posix(.ENETDOWN))

        // Assert (CODE_AUDIT_18 §5.15)
        #expect(env.controller.networkModel.listenerStatus == .waiting)
        await env.controller.listenerReady()
        #expect(env.controller.networkModel.listenerStatus == .running)
        env.controller.stopStreaming()
    }

    @Test("Only this session's reconnect services are dialed")
    func onlyOwnSessionIsDialed() async {
        // Arrange
        let factory = BrowserConnectionFactorySpy()
        let env = await MasterNetworkControllerTestEnvironment.create(
            browserConnectionBuilder: { endpoint, _, _ in factory.makeConnection(endpoint: endpoint) }
        )
        env.controller.startStreaming(passcode: "1234")
        let sessionId = env.controller.networkModel.sessionId
        let own = BrowserGameModel(id: UUID(), endpointName: "Own", connectionMode: .proxy, sessionId: sessionId)
        let foreign = BrowserGameModel(id: UUID(), endpointName: "Foreign", connectionMode: .proxy, sessionId: UUID().uuidString)
        let legacy = BrowserGameModel(id: UUID(), endpointName: "Legacy", connectionMode: .proxy)

        // Act
        env.controller.refresh(games: [own, foreign, legacy])

        // Assert
        #expect(factory.endpoints.count == 1)
        #expect(factory.endpoints.first.map { "\($0)" }?.contains("Own") == true)
        env.controller.stopStreaming()
    }

    @Test("A restarted game with the same code redials the players of the previous run")
    func restartedGameRedialsPreviousPlayers() async {
        // Arrange
        let factory = BrowserConnectionFactorySpy()
        let env = await MasterNetworkControllerTestEnvironment.create(
            browserConnectionBuilder: { endpoint, _, _ in factory.makeConnection(endpoint: endpoint) }
        )
        env.controller.startStreaming(passcode: "1234")
        let previousSession = env.controller.networkModel.sessionId
        env.controller.stopStreaming()
        let waitingPlayer = BrowserGameModel(id: UUID(), endpointName: "Waiting", connectionMode: .proxy, sessionId: previousSession)

        // Act
        env.controller.startStreaming(passcode: "1234")
        env.controller.refresh(games: [waitingPlayer])

        // Assert
        #expect(env.controller.networkModel.sessionId == previousSession)
        #expect(factory.endpoints.count == 1)
        env.controller.stopStreaming()
    }

    @Test("A new join code starts a new session")
    func newCodeStartsNewSession() async {
        // Arrange
        let factory = BrowserConnectionFactorySpy()
        let env = await MasterNetworkControllerTestEnvironment.create(
            browserConnectionBuilder: { endpoint, _, _ in factory.makeConnection(endpoint: endpoint) }
        )
        env.controller.startStreaming(passcode: "1234")
        let previousSession = env.controller.networkModel.sessionId
        env.controller.stopStreaming()
        let waitingPlayer = BrowserGameModel(id: UUID(), endpointName: "Waiting", connectionMode: .proxy, sessionId: previousSession)

        // Act
        env.controller.startStreaming(passcode: "5678")
        env.controller.refresh(games: [waitingPlayer])

        // Assert
        #expect(env.controller.networkModel.sessionId != previousSession)
        #expect(factory.endpoints.isEmpty)
        env.controller.stopStreaming()
    }

    @Test("Outbound dials are capped and never use up the inbound join slots")
    func outboundDialsAreCapped() async {
        // Arrange
        let factory = BrowserConnectionFactorySpy()
        let env = await MasterNetworkControllerTestEnvironment.create(
            browserConnectionBuilder: { endpoint, _, _ in factory.makeConnection(endpoint: endpoint) }
        )
        env.controller.startStreaming(passcode: "1234")

        // Act
        for index in 0..<(MasterNetworkController.maximumOutboundDials + 4) {
            env.controller.connectToPlayer(endpoint: .service(name: "Fallback\(index)", type: GameServiceType.master.serviceName, domain: "local.", interface: nil))
        }
        await env.controller.newConnection(for: .game(to: .hostPort(host: "localhost", port: .any), passcode: "1234"))

        // Assert
        #expect(factory.endpoints.count == MasterNetworkController.maximumOutboundDials)
        #expect(env.controller.networkModel.connections.count == MasterNetworkController.maximumOutboundDials + 1)
        env.controller.stopStreaming()
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

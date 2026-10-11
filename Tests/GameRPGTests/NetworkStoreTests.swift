// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Network
import Testing

@testable import GameRPG

/// Test environment for NetworkController tests.
@MainActor
struct NetworkStoreTestEnvironment {
    let masterDelegateSpy: MasterNetworkStoreDelegateMock
    let playerDelegateSpy: PlayerNetworkStoreDelegateMock
    let masterNetworkSpy: MasterNetworkControllableMock
    let playerNetworkSpy: PlayerStoreAbstractionMock
    let networkController: GameNetworkController

    /// Creates a GameNetworkController with spy dependencies
    static func create(
        includesMasterDelegate: Bool = true
    ) async throws -> NetworkStoreTestEnvironment {
        let masterDelegateSpy = MasterNetworkStoreDelegateMock()
        let playerDelegateSpy = PlayerNetworkStoreDelegateMock()
        let masterNetworkSpy = MasterNetworkControllableMock()
        let playerNetworkSpy = PlayerStoreAbstractionMock()

        let networkController = GameNetworkController(
            name: "Hello Test",
            proxy: false,
            masterBuilder: { _, _ in masterNetworkSpy },
            playerBuilder: { _, _ in playerNetworkSpy }
        )
        if includesMasterDelegate {
            networkController.model.setMasterDelegate(masterDelegateSpy)
        }
        networkController.model.setPlayerDelegate(playerDelegateSpy)

        return NetworkStoreTestEnvironment(
            masterDelegateSpy: masterDelegateSpy,
            playerDelegateSpy: playerDelegateSpy,
            masterNetworkSpy: masterNetworkSpy,
            playerNetworkSpy: playerNetworkSpy,
            networkController: networkController
        )
    }
}

@Suite("Network controller tests")
@MainActor
struct NetworkStoreTests {
    enum SharePlayPlayerIngress: CaseIterable, Sendable {
        case messenger
        case journal
    }

    enum DeferredPeerGroupEventKind: CaseIterable, Sendable {
        case mapPin
        case spaceTransform
        case dice
    }

    // Test data
    let masterGameNetworkModel = GameNetworkModel(
        counter: 1,
        proxyCounter: 0,
        type: .reveal,
        subType: .show,
        gameConfig: .master,
        data: NetworkCodableDataType(id: UUID(), type: .none, version: 0, data: nil)
    )

    let playerGameNetworkModel = GameNetworkModel(
        counter: 2,
        proxyCounter: 0,
        type: .reveal,
        subType: .show,
        gameConfig: .player,
        data: NetworkCodableDataType(id: UUID(), type: .none, version: 0, data: nil)
    )

    @Test("Master game network flow")
    func masterGame() async throws {
        // Arrange
        let env = try await NetworkStoreTestEnvironment.create()

        // Act & Assert - Start master game
        await env.networkController.startMasterGame(game: .master, titleImage: nil, passcode: "1234")
        #expect(env.masterNetworkSpy.calledStartStreaming == 1)

        // Act & Assert - Master ready
        await env.networkController.masterReady(for: ConnectionController.ID())
        #expect(env.masterDelegateSpy.calledReady == 1)

        // Act & Assert - Send to specific player
        let connectionId = ConnectionController.ID()
        await env.networkController.sendPlayer(masterGameNetworkModel, to: connectionId)
        #expect(env.masterNetworkSpy.calledSendResponseId == 1)

        // Act & Assert - An undeliverable direct id is ignored; it must not leak a
        // targeted payload to every other transport.
        env.masterNetworkSpy.sendResponseIdResult = false
        await env.networkController.sendPlayer(masterGameNetworkModel, to: ConnectionController.ID())
        #expect(env.masterNetworkSpy.calledSendResponseId == 2)
        #expect(env.masterNetworkSpy.calledSendResponseAll == 0)
        env.masterNetworkSpy.sendResponseIdResult = true

        // Act & Assert - Send to all players
        await env.networkController.sendPlayer(data: masterGameNetworkModel)
        #expect(env.masterNetworkSpy.calledSendResponseAll == 1)

        // Act & Assert - Master received data. Only a player's group event is relayed to
        // the other connections; everything else is for the master alone.
        await env.networkController.masterReceived(
            data: masterGameNetworkModel.encodeData(),
            for: ConnectionController.ID()
        )
        #expect(env.masterNetworkSpy.calledSendResponseExcept == 0)
        #expect(env.masterDelegateSpy.calledReceived == 1)

        // Act & Assert - Stop game when not streaming
        await env.networkController.stopGame()
        #expect(env.masterNetworkSpy.calledStopStreaming == 0)

        // Act & Assert - Stop game when streaming
        env.masterNetworkSpy.networkModel.reset(isStreaming: true)
        await env.networkController.stopGame()
        #expect(env.masterNetworkSpy.calledStopStreaming == 1)
    }

    @Test(
        "Player Character synchronization is delivered to the master without LAN fan-out",
        arguments: [false, true]
    )
    func playerCharacterSynchronizationIsMasterOnlyOnLocalNetwork(includesPackage: Bool) async throws {
        // Given
        let env = try await NetworkStoreTestEnvironment.create()
        let masterId = UUID()
        let playerId = UUID()
        let characterId = UUID()
        let message = GameNetworkModel(
            counter: 3,
            proxyCounter: 0,
            type: .update,
            subType: .store,
            masterId: masterId,
            sender: GameSenderModel(
                id: playerId,
                role: .player,
                name: "Player",
                characterId: characterId
            ),
            data: NetworkCodableDataType(
                id: characterId,
                type: .value,
                version: 42,
                data: includesPackage ? Data("Character package".utf8) : nil
            )
        )

        // When
        await env.networkController.masterReceived(
            data: message.encodeData(),
            for: ConnectionController.ID()
        )

        // Then
        #expect(env.masterNetworkSpy.calledSendResponseExcept == 0)
        #expect(env.masterDelegateSpy.calledReceived == 1)
    }

    @Test("Player availability reports and asset requests stop at the master")
    func masterOnlyPlayerTrafficIsNotRelayedToLanPeers() async throws {
        // Given
        let env = try await NetworkStoreTestEnvironment.create()
        let player = GameSenderModel(id: UUID(), role: .player, name: "Player", characterId: nil)
        let report = GameNetworkModel(
            counter: 10,
            proxyCounter: 0,
            type: .update,
            subType: .photoList,
            masterId: UUID(),
            sender: player,
            data: NetworkCodableDataType(id: UUID(), type: .photo, version: 1, data: Data())
        )
        let request = GameNetworkModel(
            counter: 11,
            proxyCounter: 0,
            type: .reveal,
            subType: .show,
            masterId: report.masterId,
            sender: player,
            data: NetworkCodableDataType(id: UUID(), type: .photo, version: 1)
        )

        // When
        await env.networkController.masterReceived(
            data: report.encodeData(),
            for: ConnectionController.ID()
        )
        await env.networkController.masterReceived(
            data: request.encodeData(),
            for: ConnectionController.ID()
        )

        // Then
        #expect(env.masterNetworkSpy.calledSendResponseExcept == 0)
        #expect(env.masterDelegateSpy.calledReceived == 2)
    }

    @Test("Only a player role can publish peer-visible dice")
    func observerDiceIsNotRelayedButPlayerDiceIs() async throws {
        // Given
        let env = try await NetworkStoreTestEnvironment.create()
        let masterId = UUID()
        let diceData = NetworkCodableDataType(id: UUID(), type: .dice, version: 1, data: Data([1]))
        let observerDice = GameNetworkModel(
            counter: 12,
            proxyCounter: 0,
            type: .update,
            subType: .generic,
            masterId: masterId,
            sender: GameSenderModel(id: UUID(), role: .observer, name: "Observer", characterId: nil),
            data: diceData
        )
        let playerDice = GameNetworkModel(
            counter: 13,
            proxyCounter: 0,
            type: .update,
            subType: .generic,
            masterId: masterId,
            sender: GameSenderModel(id: UUID(), role: .player, name: "Player", characterId: nil),
            data: diceData
        )

        // When
        await env.networkController.masterReceived(
            data: observerDice.encodeData(),
            for: ConnectionController.ID()
        )
        #expect(env.masterNetworkSpy.calledSendResponseExcept == 0)
        await env.networkController.masterReceived(
            data: playerDice.encodeData(),
            for: ConnectionController.ID()
        )

        // Then
        #expect(env.masterNetworkSpy.calledSendResponseExcept == 1)
        #expect(env.masterDelegateSpy.calledReceived == 2)
    }

    @Test("Player Dice show and store commands never cross the LAN bridge")
    func malformedPlayerDiceCommandsAreNotBridged() async throws {
        // Given
        let env = try await NetworkStoreTestEnvironment.create()
        let player = GameSenderModel(
            id: UUID(),
            role: .player,
            name: "Player",
            characterId: nil
        )
        let payload = NetworkCodableDataType(
            id: UUID(),
            type: .dice,
            version: 1,
            data: Data([0xD1, 0xCE])
        )

        // When
        for (counter, subType) in [(21, RPGMessageActionType.show), (22, .store)] {
            let message = GameNetworkModel(
                counter: counter,
                proxyCounter: 0,
                type: .update,
                subType: subType,
                masterId: UUID(),
                sender: player,
                data: payload
            )
            await env.networkController.masterReceived(
                data: message.encodeData(),
                for: ConnectionController.ID()
            )
        }

        // Then: the master may inspect the malformed input, but it is never
        // broadcast to sibling players or SharePlay.
        #expect(env.masterNetworkSpy.calledSendResponseExcept == 0)
        #expect(env.masterDelegateSpy.calledReceived == 2)
    }

    @Test("A SharePlay-targeted response never falls through to LAN")
    func sharePlayTargetDoesNotUseLanBroadcast() async throws {
        // Given
        let env = try await NetworkStoreTestEnvironment.create()
        var response = masterGameNetworkModel
        response.targetId = UUID()

        // When
        await env.networkController.sendAsset(
            response,
            to: .sharePlay(UUID())
        )

        // Then
        #expect(env.masterNetworkSpy.calledSendResponseId == 0)
        #expect(env.masterNetworkSpy.calledSendResponseAll == 0)
        #expect(env.playerDelegateSpy.calledReceived == 0)
    }

    @Test("A newly active SharePlay participant is replayed by transport origin")
    func sharePlayJoinPreservesTransportParticipantIdentity() async throws {
        // Given
        let env = try await NetworkStoreTestEnvironment.create()
        let participantId = UUID()

        // When
        await env.networkController.sharePlayJoinedPlayer(id: participantId)

        // Then
        #expect(env.masterDelegateSpy.calledReady == 1)
        #expect(env.masterDelegateSpy.readyOrigins == [.sharePlay(participantId)])
        #expect(env.masterNetworkSpy.calledSendResponseId == 0)
        #expect(env.masterNetworkSpy.calledSendResponseAll == 0)
    }

    @Test("SharePlay spoofed master is neither applied nor bridged to LAN")
    func sharePlaySpoofedMasterIsNotAppliedOrBridged() async throws {
        // Given - establish the real master before the attacker broadcasts.
        let env = try await PlayerControllerTestEnvironment.create()
        env.networkController.setupLocal()
        let masterId = UUID()
        let attackerId = UUID()
        let bootstrap = Self.masterBroadcast(
            counter: 1,
            masterId: masterId,
            playerId: env.gameConfig.id,
            title: "Real game"
        )
        await env.playerController.receivedSharePlay(bootstrap, participantId: UUID())

        let malicious = Self.masterBroadcast(
            counter: 2,
            masterId: masterId,
            senderId: attackerId,
            playerId: attackerId,
            title: "Spoofed game"
        )

        // When - exercise both Messenger and Journal receive paths.
        await env.networkController.routeSharePlayUpdate(malicious, id: UUID())
        await env.networkController.routeSharePlayFileUpdate(malicious)

        // Then
        #expect(env.root.gameModel.gameConfig.master.id == masterId)
        #expect(env.root.gameModel.gameConfig.master.adventureTitle == "Real game")
        #expect(!env.root.gameModel.gameRoster.players.contains { $0.id == attackerId })
        #expect(env.masterNetworkSpy.calledSendResponseAll == 0)
    }

    @Test(
        "GM-local player accepts master traffic only through local delivery",
        arguments: SharePlayPlayerIngress.allCases
    )
    func gameMasterLocalPlayerRejectsInboundSharePlayMaster(
        ingress: SharePlayPlayerIngress
    ) async throws {
        // Given - setupLocal identifies the co-located PlayerController on the
        // authoritative game-master device.
        let env = try await NetworkStoreTestEnvironment.create()
        env.networkController.setupLocal()

        // When - a remote participant copies the public master envelope.
        switch ingress {
        case .messenger:
            await env.networkController.routeSharePlayUpdate(
                masterGameNetworkModel,
                id: UUID()
            )
        case .journal:
            await env.networkController.routeSharePlayFileUpdate(masterGameNetworkModel)
        }

        // Then - it never reaches the co-located player or either bridge side.
        #expect(env.playerDelegateSpy.calledReceived == 0)
        #expect(env.playerDelegateSpy.calledFileReceived == 0)
        #expect(env.masterDelegateSpy.calledReceived == 0)
        #expect(env.masterDelegateSpy.calledFileReceived == 0)
        #expect(env.masterNetworkSpy.calledSendResponseAll == 0)

        // And the real master's explicit local delivery remains intact.
        await env.networkController.sendPlayer(data: masterGameNetworkModel)
        #expect(env.playerDelegateSpy.calledReceived == 1)
        #expect(env.playerDelegateSpy.calledFileReceived == 0)
    }

    @Test("Player accepts one complete master bootstrap and pins that session")
    func playerBootstrapPinsMasterAuthority() async throws {
        // Given
        let env = try await PlayerControllerTestEnvironment.create()
        let masterId = UUID()
        let alternateMasterId = UUID()
        let masterParticipantId = UUID()
        let first = Self.masterBroadcast(
            counter: 10,
            masterId: masterId,
            playerId: env.gameConfig.id,
            title: "First state"
        )
        let competing = Self.masterBroadcast(
            counter: 11,
            masterId: alternateMasterId,
            playerId: env.gameConfig.id,
            title: "Competing state"
        )
        let laterFromPinnedMaster = Self.masterBroadcast(
            counter: 12,
            masterId: masterId,
            playerId: env.gameConfig.id,
            title: "Updated state"
        )

        // When
        await env.playerController.receivedSharePlay(
            first,
            participantId: masterParticipantId
        )
        await env.playerController.receivedSharePlay(
            competing,
            participantId: UUID()
        )

        // Then - another internally consistent master cannot replace the first.
        #expect(env.root.gameModel.gameConfig.master.id == masterId)
        #expect(env.root.gameModel.gameConfig.master.adventureTitle == "First state")

        // And later broadcasts from the pinned master remain valid.
        await env.playerController.receivedSharePlay(
            laterFromPinnedMaster,
            participantId: masterParticipantId
        )
        #expect(env.root.gameModel.gameConfig.master.id == masterId)
        #expect(env.root.gameModel.gameConfig.master.adventureTitle == "Updated state")
    }

    @Test("Player game network flow")
    func playerGame() async throws {
        // Arrange
        let env = try await NetworkStoreTestEnvironment.create()

        // Act & Assert - Start player game with no device (should fail)
        let result = await env.networkController.startPlayerGame(to: nil, passcode: "1234")
        #expect(result == false)
        #expect(env.playerNetworkSpy.calledToggleConnection == 0)

        // Act & Assert - Start player game with device (should succeed)
        let connectResult = await env.networkController.startPlayerGame(
            to: BrowserGameModel(id: UUID(), endpointName: "MasterTestDevice", connectionMode: .observer),
            passcode: "1234"
        )
        #expect(connectResult)
        #expect(env.playerNetworkSpy.calledToggleConnection == 1)

        // Act & Assert - Player ready
        await env.networkController.playerReady()
        #expect(env.playerDelegateSpy.calledReady == 1)

        // Act & Assert - Send to master
        await env.networkController.sendMaster(data: playerGameNetworkModel)
        #expect(env.playerNetworkSpy.calledRequest == 1)

        // Act & Assert - Player received data
        await env.networkController.playerReceived(data: playerGameNetworkModel.encodeData())
        #expect(env.playerDelegateSpy.calledReceived == 1)

        // Act & Assert - Player lost master
        await env.networkController.playerLostMaster()
        #expect(env.playerDelegateSpy.calledLostConnection == 1)

        // Act & Assert - Stop game
        await env.networkController.stopGame()
        #expect(env.playerNetworkSpy.calledStop == 1)
    }

    @Test("SharePlay messenger routing completes before receiving the next message")
    func sharePlayMessengerRoutingCompletesBeforeReceivingNextMessage() async throws {
        let env = try await NetworkStoreTestEnvironment.create()

        await env.networkController.handleUpdate(masterGameNetworkModel, id: UUID())

        #expect(env.playerDelegateSpy.calledReceived == 1)
    }

    private static func masterBroadcast(
        counter: Int,
        masterId: UUID,
        senderId: UUID? = nil,
        playerId: UUID,
        title: String
    ) -> GameNetworkModel {
        GameNetworkModel(
            counter: counter,
            proxyCounter: 0,
            type: .update,
            subType: .ok,
            masterId: masterId,
            sender: GameSenderModel(
                id: senderId ?? masterId,
                role: .master,
                name: "Master",
                characterId: nil
            ),
            masterState: GameMasterStateModel(
                state: .started,
                adventureId: nil,
                adventureTitle: title,
                players: [PlayerGameModel(id: playerId, type: .player, name: "Player")],
                controls: [],
                features: GameFeatureModel()
            ),
            data: NetworkCodableDataType(id: UUID(), type: .setting, version: 0)
        )
    }

}
#endif

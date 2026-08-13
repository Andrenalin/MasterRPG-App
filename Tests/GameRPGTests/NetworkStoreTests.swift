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
        await env.networkController.sendPlayer(data: masterGameNetworkModel, fileJournal: false)
        #expect(env.masterNetworkSpy.calledSendResponseAll == 1)

        // Act & Assert - Master received data
        await env.networkController.masterReceived(
            data: masterGameNetworkModel.encodeData(),
            for: ConnectionController.ID(),
            fileJournal: false
        )
        #expect(env.masterNetworkSpy.calledSendResponseExcept == 1)
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
            for: ConnectionController.ID(),
            fileJournal: false
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
            audience: .master,
            data: NetworkCodableDataType(id: UUID(), type: .photo, version: 1, data: Data())
        )
        let request = GameNetworkModel(
            counter: 11,
            proxyCounter: 0,
            type: .reveal,
            subType: .show,
            masterId: report.masterId,
            sender: player,
            audience: .master,
            purpose: .assetRequest,
            data: NetworkCodableDataType(id: UUID(), type: .photo, version: 1)
        )

        // When
        await env.networkController.masterReceived(
            data: report.encodeData(),
            for: ConnectionController.ID(),
            fileJournal: false
        )
        await env.networkController.masterReceived(
            data: request.encodeData(),
            for: ConnectionController.ID(),
            fileJournal: false
        )

        // Then
        #expect(env.masterNetworkSpy.calledSendResponseExcept == 0)
        #expect(env.masterDelegateSpy.calledReceived == 2)
    }

    @Test(
        "Explicit group asset requests cannot enter peer file-presentation routes",
        arguments: [NetworkModules.photo, .pdf, .space]
    )
    func explicitGroupAssetRequestIsNotRelayedToPeers(module: NetworkModules) async throws {
        // Given
        let masterId = UUID()
        let playerId = UUID()
        let request = GameNetworkModel(
            counter: 12,
            proxyCounter: 0,
            type: .reveal,
            subType: .show,
            masterId: masterId,
            sender: GameSenderModel(
                id: playerId,
                role: .player,
                name: "Requesting player",
                characterId: nil
            ),
            audience: .group,
            purpose: .assetRequest,
            data: NetworkCodableDataType(
                id: UUID(),
                type: module,
                version: 7,
                data: Data("untrusted peer bytes".utf8)
            )
        )
        #expect(request.audience == .group)
        #expect(request.effectiveAudience == .master)
        #expect(request.isPlayerFileReveal)
        #expect(!request.isPlayerFilePresentationEvent)
        #expect(!GameNetworkController.shouldRelayToLAN(request))

        // When - LAN input still reaches the master, but not sibling LAN peers.
        let lan = try await NetworkStoreTestEnvironment.create()
        await lan.networkController.masterReceived(
            data: request.encodeData(),
            for: ConnectionController.ID(),
            fileJournal: true
        )

        // Then
        #expect(lan.masterDelegateSpy.calledReceived == 1)
        #expect(lan.masterNetworkSpy.calledSendResponseExcept == 0)

        // When - SharePlay physically broadcasts the malformed request.
        let sharePlayPeer = try await NetworkStoreTestEnvironment.create()
        await sharePlayPeer.networkController.routeSharePlayUpdate(request, id: playerId)
        await sharePlayPeer.networkController.routeSharePlayFileUpdate(request)

        // Then - Messenger may reach the master as a repair request, but an
        // anonymous player Journal callback is not a valid repair transport.
        #expect(sharePlayPeer.masterDelegateSpy.calledReceived == 1)
        #expect(sharePlayPeer.masterDelegateSpy.calledFileReceived == 0)
        #expect(sharePlayPeer.playerDelegateSpy.calledReceived == 0)
        #expect(sharePlayPeer.playerDelegateSpy.calledFileReceived == 0)

        // When - A game-master device bridges the same SharePlay session to LAN.
        let sharePlayBridge = try await NetworkStoreTestEnvironment.create()
        sharePlayBridge.networkController.setupLocal()
        await sharePlayBridge.networkController.routeSharePlayUpdate(request, id: playerId)
        await sharePlayBridge.networkController.routeSharePlayFileUpdate(request)

        // Then
        #expect(sharePlayBridge.masterNetworkSpy.calledSendResponseAll == 0)

        // And a genuine peer presentation keeps the exact existing route.
        var presentation = request
        presentation.purpose = .event
        #expect(presentation.isPlayerFilePresentationEvent)
        #expect(GameNetworkController.shouldRelayToLAN(presentation))
    }

    @Test(
        "Explicit group cannot widen protocol-defined master-only player traffic",
        arguments: [
            NetworkModules.audio,
            .dice,
            .map,
            .pdf,
            .photo,
            .space,
            .table,
            .weather
        ]
    )
    func explicitGroupCannotWidenAssetRequest(module: NetworkModules) {
        // Given
        let request = GameNetworkModel(
            counter: 1,
            proxyCounter: 0,
            type: .reveal,
            subType: .show,
            masterId: UUID(),
            sender: GameSenderModel(
                id: UUID(),
                role: .player,
                name: "Player",
                characterId: nil
            ),
            audience: .group,
            purpose: .assetRequest,
            data: NetworkCodableDataType(id: UUID(), type: module, version: 1)
        )

        // Then
        #expect(request.audience == .group)
        #expect(request.effectiveAudience == .master)
        #expect(!GameNetworkController.shouldRelayToLAN(request))
    }

    @Test("Explicit group preserves valid player events but not acknowledgements or reports")
    func explicitGroupHonorsHardProtocolInvariants() {
        // Given
        let player = GameSenderModel(id: UUID(), role: .player, name: "Player", characterId: nil)
        let masterId = UUID()
        let diceEvent = GameNetworkModel(
            counter: 1,
            proxyCounter: 0,
            type: .update,
            subType: .generic,
            masterId: masterId,
            sender: player,
            audience: .group,
            data: NetworkCodableDataType(id: UUID(), type: .dice, version: 1, data: Data([1]))
        )
        let photoEvent = GameNetworkModel(
            counter: 2,
            proxyCounter: 0,
            type: .reveal,
            subType: .show,
            masterId: masterId,
            sender: player,
            audience: .group,
            purpose: .event,
            data: NetworkCodableDataType(id: UUID(), type: .photo, version: 1)
        )
        var acknowledgement = photoEvent
        acknowledgement.subType = .ok
        var report = photoEvent
        report.type = .update
        report.subType = .photoList

        // Then
        #expect(diceEvent.effectiveAudience == .group)
        #expect(GameNetworkController.shouldRelayToLAN(diceEvent))
        #expect(photoEvent.effectiveAudience == .group)
        #expect(GameNetworkController.shouldRelayToLAN(photoEvent))
        #expect(acknowledgement.effectiveAudience == .master)
        #expect(!GameNetworkController.shouldRelayToLAN(acknowledgement))
        #expect(report.effectiveAudience == .master)
        #expect(!GameNetworkController.shouldRelayToLAN(report))
    }

    @Test("Map pin and Space transform are small player group events")
    func smallPlayerStateEventsUseGroupRouting() {
        let masterID = UUID()
        let sender = GameSenderModel(
            id: UUID(),
            role: .player,
            name: "Player",
            characterId: nil
        )
        let mapPin = GameNetworkModel(
            counter: 3,
            proxyCounter: 0,
            type: .update,
            subType: .mapPin,
            masterId: masterID,
            sender: sender,
            data: NetworkCodableDataType(
                id: UUID(),
                type: .map,
                version: 1,
                data: Data([1])
            )
        )
        let transform = GameNetworkModel(
            counter: 4,
            proxyCounter: 0,
            type: .update,
            subType: .spaceTransform,
            masterId: masterID,
            sender: sender,
            data: NetworkCodableDataType(
                id: UUID(),
                type: .space,
                version: 1,
                data: Data([2])
            )
        )

        #expect(mapPin.effectiveAudience == .group)
        #expect(GameNetworkController.shouldRelayToLAN(mapPin))
        #expect(mapPin.isDeferrablePlayerGroupEvent)
        #expect(transform.effectiveAudience == .group)
        #expect(GameNetworkController.shouldRelayToLAN(transform))
        #expect(transform.isDeferrablePlayerGroupEvent)

        var mismatchedMapPin = mapPin
        mismatchedMapPin.data = NetworkCodableDataType(
            id: mapPin.data.id,
            type: .space,
            version: mapPin.data.version,
            data: mapPin.data.data
        )
        var mismatchedTransform = transform
        mismatchedTransform.data = NetworkCodableDataType(
            id: transform.data.id,
            type: .map,
            version: transform.data.version,
            data: transform.data.data
        )
        var emptyMapPin = mapPin
        emptyMapPin.data = NetworkCodableDataType(
            id: mapPin.data.id,
            type: .map,
            version: mapPin.data.version
        )
        var forgedRepair = mapPin
        forgedRepair.purpose = .assetRequest
        forgedRepair.audience = .group
        var futureTransform = transform
        futureTransform.timestamp = Date.now.timeIntervalSince1970 +
            GameNetworkModel.maximumFutureEventTimestampSkew + 1

        #expect(mismatchedMapPin.effectiveAudience == .master)
        #expect(!GameNetworkController.shouldRelayToLAN(mismatchedMapPin))
        #expect(!mismatchedMapPin.isDeferrablePlayerGroupEvent)
        #expect(mismatchedTransform.effectiveAudience == .master)
        #expect(!GameNetworkController.shouldRelayToLAN(mismatchedTransform))
        #expect(!mismatchedTransform.isDeferrablePlayerGroupEvent)
        #expect(emptyMapPin.effectiveAudience == .master)
        #expect(!GameNetworkController.shouldRelayToLAN(emptyMapPin))
        #expect(!emptyMapPin.isDeferrablePlayerGroupEvent)
        #expect(forgedRepair.effectiveAudience == .master)
        #expect(!GameNetworkController.shouldRelayToLAN(forgedRepair))
        #expect(!forgedRepair.isDeferrablePlayerGroupEvent)
        #expect(futureTransform.effectiveAudience == .group)
        #expect(!GameNetworkController.shouldRelayToLAN(futureTransform))
        #expect(!futureTransform.isDeferrablePlayerGroupEvent)
    }

    @Test(
        "SharePlay player Group event arriving before its roster entry is released once",
        arguments: DeferredPeerGroupEventKind.allCases
    )
    func sharePlayPlayerGroupEventWaitsForNextRosterUpdate(
        kind: DeferredPeerGroupEventKind
    ) async throws {
        // Given
        let env = try await NetworkStoreTestEnvironment.create(
            includesMasterDelegate: false
        )
        env.playerDelegateSpy.authoritativeSharePlayRoster = []
        let masterID = UUID()
        let masterParticipantID = UUID()
        let playerID = UUID()
        let playerParticipantID = UUID()
        let event = Self.deferredPeerGroupEvent(
            kind: kind,
            masterID: masterID,
            playerID: playerID,
            counter: 7
        )

        // When - Messenger surfaces the peer event before the master's roster.
        await env.networkController.routeSharePlayUpdate(
            event,
            id: playerParticipantID
        )

        // Then - it has not entered the player controller or transport binding.
        #expect(env.playerDelegateSpy.receivedSharePlayHistory.isEmpty)

        // When - the next authenticated master state includes that player.
        let rosterUpdate = Self.rosterBroadcast(
            counter: 8,
            masterID: masterID,
            players: [
                PlayerGameModel(id: playerID, type: .player, name: "Peer")
            ]
        )
        await env.networkController.routeSharePlayUpdate(
            rosterUpdate,
            id: masterParticipantID
        )

        // Then - the deferred event is revalidated and released exactly once.
        let released = env.playerDelegateSpy.receivedSharePlayHistory.filter {
            !$0.sender.isMaster
        }
        #expect(released.count == 1)
        #expect(released.first?.messageID == event.messageID)
        #expect(released.first?.subType == event.subType)
    }

    @Test("Unknown or wrong-role SharePlay player event is discarded after one roster update")
    func sharePlayUnknownPlayerGroupEventHasOneRosterWindow() async throws {
        // Given
        let env = try await NetworkStoreTestEnvironment.create(
            includesMasterDelegate: false
        )
        env.playerDelegateSpy.authoritativeSharePlayRoster = []
        let masterID = UUID()
        let masterParticipantID = UUID()
        let playerID = UUID()
        let event = Self.deferredPeerGroupEvent(
            kind: .mapPin,
            masterID: masterID,
            playerID: playerID,
            counter: 10
        )
        await env.networkController.routeSharePlayUpdate(event, id: UUID())

        // When - the next roster update knows the identity only as an observer.
        await env.networkController.routeSharePlayUpdate(
            Self.rosterBroadcast(
                counter: 11,
                masterID: masterID,
                players: [
                    PlayerGameModel(
                        id: playerID,
                        type: .observer,
                        name: "Observer"
                    )
                ]
            ),
            id: masterParticipantID
        )

        // And even a later update changing that identity to player cannot
        // resurrect an event that failed its one authoritative revalidation.
        await env.networkController.routeSharePlayUpdate(
            Self.rosterBroadcast(
                counter: 12,
                masterID: masterID,
                players: [
                    PlayerGameModel(id: playerID, type: .player, name: "Player")
                ]
            ),
            id: masterParticipantID
        )

        #expect(env.playerDelegateSpy.receivedSharePlayHistory.allSatisfy {
            $0.sender.isMaster
        })
    }

    @Test("SharePlay pre-roster Group event storage is bounded")
    func sharePlayDeferredPlayerGroupEventStorageIsBounded() async throws {
        // Given
        let env = try await NetworkStoreTestEnvironment.create(
            includesMasterDelegate: false
        )
        env.playerDelegateSpy.authoritativeSharePlayRoster = []
        let masterID = UUID()
        let masterParticipantID = UUID()
        let players = (0..<40).map { index in
            PlayerGameModel(id: UUID(), type: .player, name: "Peer \(index)")
        }

        // When - more valid events race the roster than the transport retains.
        for (index, player) in players.enumerated() {
            await env.networkController.routeSharePlayUpdate(
                Self.deferredPeerGroupEvent(
                    kind: .dice,
                    masterID: masterID,
                    playerID: player.id,
                    counter: index + 1
                ),
                id: UUID()
            )
        }
        await env.networkController.routeSharePlayUpdate(
            Self.rosterBroadcast(
                counter: 50,
                masterID: masterID,
                players: players
            ),
            id: masterParticipantID
        )

        // Then - the fixed 32-event cap prevents unbounded growth.
        let releasedPlayerEvents = env.playerDelegateSpy.receivedSharePlayHistory.filter {
            !$0.sender.isMaster
        }
        #expect(releasedPlayerEvents.count == 32)
    }

    @Test("Oversized SharePlay pre-roster Group event is rejected")
    func sharePlayOversizedDeferredPlayerGroupEventIsRejected() async throws {
        // Given
        let env = try await NetworkStoreTestEnvironment.create(
            includesMasterDelegate: false
        )
        env.playerDelegateSpy.authoritativeSharePlayRoster = []
        let masterID = UUID()
        let masterParticipantID = UUID()
        let playerID = UUID()
        var event = Self.deferredPeerGroupEvent(
            kind: .spaceTransform,
            masterID: masterID,
            playerID: playerID,
            counter: 1
        )
        event.data = NetworkCodableDataType(
            id: event.data.id,
            type: .space,
            version: event.data.version,
            data: Data(repeating: 1, count: 64 * 1_024 + 1)
        )

        // When
        await env.networkController.routeSharePlayUpdate(event, id: UUID())
        await env.networkController.routeSharePlayUpdate(
            Self.rosterBroadcast(
                counter: 2,
                masterID: masterID,
                players: [
                    PlayerGameModel(id: playerID, type: .player, name: "Player")
                ]
            ),
            id: masterParticipantID
        )

        // Then
        #expect(env.playerDelegateSpy.receivedSharePlayHistory.allSatisfy {
            $0.sender.isMaster
        })
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
            audience: .group,
            data: diceData
        )
        let playerDice = GameNetworkModel(
            counter: 13,
            proxyCounter: 0,
            type: .update,
            subType: .generic,
            masterId: masterId,
            sender: GameSenderModel(id: UUID(), role: .player, name: "Player", characterId: nil),
            audience: .group,
            data: diceData
        )

        // When
        await env.networkController.masterReceived(
            data: observerDice.encodeData(),
            for: ConnectionController.ID(),
            fileJournal: false
        )
        #expect(env.masterNetworkSpy.calledSendResponseExcept == 0)
        await env.networkController.masterReceived(
            data: playerDice.encodeData(),
            for: ConnectionController.ID(),
            fileJournal: false
        )

        // Then
        #expect(env.masterNetworkSpy.calledSendResponseExcept == 1)
        #expect(env.masterDelegateSpy.calledReceived == 2)
    }

    @Test("Player Dice routing exposes only complete roll events to the group")
    func playerDiceGroupShapeIsExact() {
        // Given
        let masterID = UUID()
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
        let roll = GameNetworkModel(
            counter: 1,
            proxyCounter: 0,
            type: .update,
            subType: .generic,
            masterId: masterID,
            sender: player,
            audience: .group,
            purpose: .event,
            data: payload
        )
        var legacyRoll = roll
        legacyRoll.purpose = .legacy
        var show = roll
        show.subType = .show
        var store = roll
        store.subType = .store
        var incomplete = roll
        incomplete.data = NetworkCodableDataType(
            id: payload.id,
            type: .dice,
            version: payload.version
        )
        var repair = roll
        repair.purpose = .assetRequest
        let masterShow = GameNetworkModel(
            counter: 2,
            proxyCounter: 0,
            type: .update,
            subType: .show,
            masterId: masterID,
            sender: GameSenderModel(
                id: masterID,
                role: .master,
                name: "Master",
                characterId: nil
            ),
            data: payload
        )

        // Then
        #expect(roll.isPlayerDiceGroupEvent)
        #expect(roll.effectiveAudience == .group)
        #expect(GameNetworkController.shouldRelayToLAN(roll))
        #expect(legacyRoll.isPlayerDiceGroupEvent)
        #expect(legacyRoll.effectiveAudience == .group)
        #expect(GameNetworkController.shouldRelayToLAN(legacyRoll))

        for rejected in [show, store, incomplete, repair] {
            #expect(!rejected.isPlayerDiceGroupEvent)
            #expect(rejected.effectiveAudience == .master)
            #expect(!GameNetworkController.shouldRelayToLAN(rejected))
        }

        // Master presentation commands keep their existing group route.
        #expect(masterShow.effectiveAudience == .group)
        #expect(GameNetworkController.shouldRelayToLAN(masterShow))
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
                audience: .group,
                purpose: .event,
                data: payload
            )
            await env.networkController.masterReceived(
                data: message.encodeData(),
                for: ConnectionController.ID(),
                fileJournal: false
            )
        }

        // Then: the master may inspect the malformed input, but it is never
        // broadcast to sibling players or SharePlay.
        #expect(env.masterNetworkSpy.calledSendResponseExcept == 0)
        #expect(env.masterDelegateSpy.calledReceived == 2)
    }

    @Test("A retried player group event crosses the transport bridge once")
    func duplicatePlayerEventIsNotRelayedTwice() async throws {
        let env = try await NetworkStoreTestEnvironment.create()
        let connectionID = ConnectionController.ID()
        let event = GameNetworkModel(
            counter: 13,
            proxyCounter: 0,
            type: .update,
            subType: .generic,
            masterId: UUID(),
            sender: GameSenderModel(
                id: UUID(),
                role: .player,
                name: "Player",
                characterId: nil
            ),
            data: NetworkCodableDataType(
                id: UUID(),
                type: .dice,
                version: 1,
                data: Data([1])
            )
        )
        let encoded = try #require(event.encodeData())

        await env.networkController.masterReceived(
            data: encoded,
            for: connectionID,
            fileJournal: false
        )
        await env.networkController.masterReceived(
            data: encoded,
            for: connectionID,
            fileJournal: false
        )

        #expect(env.masterNetworkSpy.calledSendResponseExcept == 1)
    }

    @Test("Different players may reuse one message UUID across the transport bridge")
    func relayAdmissionScopesMessageIdentityToSender() async throws {
        // Given: two independently generated player events happen to carry the
        // same message UUID and payload shape.
        let env = try await NetworkStoreTestEnvironment.create()
        let messageID = UUID()
        let masterID = UUID()
        let itemId = UUID()
        let firstSenderID = UUID()
        let secondSenderID = UUID()

        func event(senderID: UUID, counter: Int) -> GameNetworkModel {
            GameNetworkModel(
                messageID: messageID,
                counter: counter,
                proxyCounter: 0,
                type: .update,
                subType: .generic,
                masterId: masterID,
                sender: GameSenderModel(
                    id: senderID,
                    role: .player,
                    name: "Player",
                    characterId: nil
                ),
                data: NetworkCodableDataType(
                    id: itemId,
                    type: .dice,
                    version: 1,
                    data: Data([1])
                )
            )
        }

        // When
        await env.networkController.masterReceived(
            data: event(senderID: firstSenderID, counter: 20).encodeData(),
            for: ConnectionController.ID(),
            fileJournal: false
        )
        await env.networkController.masterReceived(
            data: event(senderID: secondSenderID, counter: 20).encodeData(),
            for: ConnectionController.ID(),
            fileJournal: false
        )

        // Then: neither sender suppresses the other's independent event.
        #expect(env.masterNetworkSpy.calledSendResponseExcept == 2)
        #expect(env.masterDelegateSpy.calledReceived == 2)
    }

    @Test("A SharePlay-targeted response never falls through to LAN")
    func sharePlayTargetDoesNotUseLanBroadcast() async throws {
        // Given
        let env = try await NetworkStoreTestEnvironment.create()
        var response = masterGameNetworkModel
        response.targetId = UUID()
        response.audience = .target

        // When
        await env.networkController.sendPlayer(
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
        await env.networkController.sendPlayer(
            data: masterGameNetworkModel,
            fileJournal: ingress == .journal
        )
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

    @Test("SharePlay player pins the physical master and resynchronizes after its rebind")
    func sharePlayMasterParticipantPinAndRebind() async throws {
        // Given - a complete master state establishes both the public logical
        // master UUID and its private GroupSession participant source.
        let env = try await PlayerControllerTestEnvironment.create()
        let masterId = UUID()
        let initialParticipantId = UUID()
        let unrelatedParticipantId = UUID()
        let replacementParticipantId = UUID()
        let first = Self.masterBroadcast(
            counter: 1,
            masterId: masterId,
            playerId: env.gameConfig.id,
            title: "Initial master"
        )
        await env.playerController.receivedSharePlay(
            first,
            participantId: initialParticipantId
        )
        // Match the normal GroupSession lifecycle, where configuration marks
        // the player connected and emits the initial availability reports.
        await env.playerController.ready()
        let initialRequestCount = env.playerNetworkSpy.calledRequest
        #expect(initialRequestCount == 4)

        // A different physical participant cannot impersonate that same
        // logical master, and an unrelated departure does not release the pin.
        let physicalSpoof = Self.masterBroadcast(
            counter: 2,
            masterId: masterId,
            playerId: env.gameConfig.id,
            title: "Spoofed master"
        )
        await env.playerController.sharePlayParticipantLeft(
            id: unrelatedParticipantId
        )
        await env.playerController.receivedSharePlay(
            physicalSpoof,
            participantId: unrelatedParticipantId
        )
        #expect(env.root.gameModel.gameConfig.master.adventureTitle == "Initial master")
        #expect(env.playerController.gameModel.lostMaster == false)

        // When the pinned source leaves, only a replacement's complete master
        // broadcast may rebind authority. A state-less command carrying the
        // copied logical UUID cannot win that race.
        await env.playerController.sharePlayParticipantLeft(
            id: initialParticipantId
        )
        #expect(env.playerController.gameModel.lostMaster)

        var stateLessSpoof = physicalSpoof
        stateLessSpoof.counter = 3
        stateLessSpoof.masterState = nil
        await env.playerController.receivedSharePlay(
            stateLessSpoof,
            participantId: unrelatedParticipantId
        )
        #expect(env.playerController.gameModel.lostMaster)
        #expect(env.playerNetworkSpy.calledRequest == initialRequestCount)

        let replacement = Self.masterBroadcast(
            counter: 4,
            masterId: masterId,
            playerId: env.gameConfig.id,
            title: "Rejoined master"
        )
        await env.playerController.receivedSharePlay(
            replacement,
            participantId: replacementParticipantId
        )

        // Then - rebinding performs the same availability handshake as ready(),
        // including scheduling Character advertisement after the four lists.
        #expect(env.root.gameModel.gameConfig.master.adventureTitle == "Rejoined master")
        #expect(env.playerController.gameModel.lostMaster == false)
        let reports = env.playerNetworkSpy.requestHistory
            .dropFirst(initialRequestCount)
            .compactMap {
            $0 as? GameNetworkModel
        }
        #expect(reports.map(\.subType) == [
            .audioList,
            .photoList,
            .pdfList,
            .spaceList
        ])
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
        await env.networkController.sendMaster(data: playerGameNetworkModel, fileJournal: false)
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

    @Test("Master Journal admission can pin a late participant without presentation side effects")
    func sharePlayFileRoutingCompletesBeforeReturningToJournal() async throws {
        // Given
        let env = try await NetworkStoreTestEnvironment.create()
        let masterID = UUID()
        let participantID = UUID()
        let full = Self.masterJournalPresentation(
            masterID: masterID,
            messageID: UUID(),
            data: Data("photo".utf8)
        )
        let metadata = try #require(
            RPGSharePlayController.masterJournalAdmissionMetadata(for: full)
        )

        // When - the anonymous Journal callback arrives first.
        await env.networkController.handleFileUpdate(full)
        #expect(env.playerDelegateSpy.calledFileReceived == 0)

        // When - Messenger later identifies the already-pinned master source.
        await env.networkController.handleUpdate(metadata, id: participantID)

        // Then
        #expect(env.playerDelegateSpy.calledMasterJournalAdmission == 1)
        #expect(env.playerDelegateSpy.pinnedSharePlayMasterParticipantID == participantID)
        #expect(env.playerDelegateSpy.calledReceived == 0)
        #expect(env.playerDelegateSpy.calledFileReceived == 1)
    }

    @Test("Authenticated deferred Journal failure keeps its recovery callback")
    func sharePlayAttachmentFailureRoutingCompletesBeforeReturningToJournal() async throws {
        // Given
        let env = try await NetworkStoreTestEnvironment.create()
        let masterID = UUID()
        let participantID = UUID()
        env.playerDelegateSpy.pinnedSharePlayMasterParticipantID = participantID
        let full = Self.masterJournalPresentation(
            masterID: masterID,
            messageID: UUID(),
            module: .weather,
            targetID: UUID(),
            data: Data("weather".utf8)
        )
        let admissionMetadata = try #require(
            RPGSharePlayController.masterJournalAdmissionMetadata(for: full)
        )
        let failureMetadata = RPGSharePlayController.journalMetadata(for: full)

        // When
        await env.networkController.handleFileLoadFailure(failureMetadata)
        #expect(env.playerDelegateSpy.calledFileLoadFailed == 0)
        await env.networkController.handleUpdate(admissionMetadata, id: participantID)

        // Then
        #expect(env.playerDelegateSpy.calledFileLoadFailed == 1)
        #expect(env.playerDelegateSpy.calledFileReceived == 0)
    }

    @Test("SharePlay messenger routing completes before receiving the next message")
    func sharePlayMessengerRoutingCompletesBeforeReceivingNextMessage() async throws {
        let env = try await NetworkStoreTestEnvironment.create()

        await env.networkController.handleUpdate(masterGameNetworkModel, id: UUID())

        #expect(env.playerDelegateSpy.calledReceived == 1)
    }

    @Test("Player Journal waits for its physically attributed Messenger metadata")
    func playerJournalWaitsForMessengerAdmission() async throws {
        // Given
        let env = try await NetworkStoreTestEnvironment.create()
        env.networkController.setupLocal()
        let participantID = UUID()
        let full = Self.playerFilePresentation(
            senderID: UUID(),
            messageID: UUID(),
            data: Data("photo".utf8)
        )
        let metadata = try #require(
            RPGSharePlayController.playerJournalAdmissionMetadata(for: full)
        )

        // When - Journal wins the transport race.
        await env.networkController.routeSharePlayFileUpdate(full)

        // Then - no anonymous Journal bytes reach a controller or LAN bridge.
        #expect(env.masterDelegateSpy.calledFileReceived == 0)
        #expect(env.playerDelegateSpy.calledFileReceived == 0)
        #expect(env.masterNetworkSpy.calledSendResponseAll == 0)

        // When - the same logical message later arrives from Messenger.
        await env.networkController.routeSharePlayUpdate(metadata, id: participantID)

        // Then - the control packet itself never enters a presentation handler
        // or LAN bridge; only the deferred full callback is released.
        #expect(env.masterDelegateSpy.calledReceived == 0)
        #expect(env.masterDelegateSpy.calledFileReceived == 1)
        let relayed = env.masterNetworkSpy.sendResponseHistory.compactMap {
            $0 as? GameNetworkModel
        }
        #expect(relayed.map { $0.data.data != nil } == [true])
    }

    @Test("Journal attachment reuse metadata remains a real presentation event")
    func journalReuseMetadataIsRoutedNormally() async throws {
        // Given
        let env = try await NetworkStoreTestEnvironment.create()
        env.networkController.setupLocal()
        let full = Self.playerFilePresentation(
            senderID: UUID(),
            messageID: UUID(),
            data: Data("photo".utf8)
        )
        let reuseMetadata = RPGSharePlayController.journalMetadata(for: full)
        #expect(!reuseMetadata.isJournalAdmissionOnly)

        // When
        await env.networkController.routeSharePlayUpdate(
            reuseMetadata,
            id: UUID()
        )

        // Then - unlike fresh-publication admission metadata, this is the
        // actual reshow event and retains the normal controller/LAN route.
        #expect(env.masterDelegateSpy.calledReceived == 1)
        #expect(env.masterDelegateSpy.calledFileReceived == 0)
        let relayed = env.masterNetworkSpy.sendResponseHistory.compactMap {
            $0 as? GameNetworkModel
        }
        #expect(relayed.count == 1)
        #expect(relayed.first?.data.data == nil)
        #expect(relayed.first?.journalAdmissionOnly == nil)
    }

    @Test("Player Journal admission rejects copied IDs with a changed fingerprint")
    func playerJournalAdmissionRequiresExactFingerprint() async throws {
        // Given
        let env = try await NetworkStoreTestEnvironment.create()
        let participantID = UUID()
        let full = Self.playerFilePresentation(
            senderID: UUID(),
            messageID: UUID(),
            data: Data("photo".utf8)
        )
        let metadata = try #require(
            RPGSharePlayController.playerJournalAdmissionMetadata(for: full)
        )
        await env.networkController.routeSharePlayUpdate(metadata, id: participantID)
        var forged = full
        forged.data = NetworkCodableDataType(
            id: UUID(),
            type: .photo,
            version: full.data.version + 1,
            data: Data("forged".utf8)
        )

        // When
        await env.networkController.routeSharePlayFileUpdate(forged)

        // Then
        #expect(env.masterDelegateSpy.calledFileReceived == 0)
        #expect(env.playerDelegateSpy.calledFileReceived == 0)
    }

    @Test("Journal admission cryptographically binds the loaded payload bytes")
    func playerJournalAdmissionRejectsChangedPayloadBytes() async throws {
        // Given
        let env = try await NetworkStoreTestEnvironment.create()
        env.networkController.setupLocal()
        let participantID = UUID()
        let full = Self.playerFilePresentation(
            senderID: UUID(),
            messageID: UUID(),
            data: Data("authentic photo".utf8)
        )
        let admission = try #require(
            RPGSharePlayController.playerJournalAdmissionMetadata(for: full)
        )
        #expect(admission.journalPayloadDigest == GameNetworkModel.journalDigest(
            for: try #require(full.data.data)
        ))
        await env.networkController.routeSharePlayUpdate(
            admission,
            id: participantID
        )

        var forged = full
        forged.journalPayloadDigest = admission.journalPayloadDigest
        forged.data = NetworkCodableDataType(
            id: full.data.id,
            type: full.data.type,
            version: full.data.version,
            data: Data("changed bytes".utf8),
            assetVersion: full.data.assetVersion,
            contentVersion: full.data.contentVersion
        )

        // When - every visible metadata field and the copied claimed digest
        // match, but the bytes loaded from Journal do not.
        await env.networkController.routeSharePlayFileUpdate(forged)

        // Then
        #expect(env.masterDelegateSpy.calledFileReceived == 0)
        #expect(env.masterNetworkSpy.sendResponseHistory.isEmpty)

        // And the rejected payload did not poison the valid admission.
        await env.networkController.routeSharePlayFileUpdate(full)
        #expect(env.masterDelegateSpy.calledFileReceived == 1)
    }

    @Test("Late join replays authenticated original Journal admissions with master first")
    func lateJoinJournalAdmissionReplayUsesExistingAttachmentIdentity() throws {
        // Given
        let masterID = UUID()
        let masterFull = Self.masterJournalPresentation(
            masterID: masterID,
            messageID: UUID(),
            data: Data("master photo".utf8)
        )
        let playerFull = Self.playerFilePresentation(
            senderID: UUID(),
            messageID: UUID(),
            data: Data("player photo".utf8)
        )
        let masterMetadata = RPGSharePlayController.journalMetadata(for: masterFull)
        let playerMetadata = RPGSharePlayController.journalMetadata(for: playerFull)
        let masterAttachmentID = UUID()
        let playerAttachmentID = UUID()
        var tracker = SharePlayJournalTracker()
        tracker.didPublish(
            module: masterMetadata.data.type,
            itemId: masterMetadata.data.id,
            version: masterMetadata.data.effectiveAssetVersion,
            attachmentId: masterAttachmentID,
            metadata: masterMetadata
        )
        tracker.didObserve(
            attachmentId: playerAttachmentID,
            metadata: playerMetadata
        )

        // Then - anonymous observed metadata is not laundered by the master.
        #expect(tracker.currentJournalMetadata().count == 1)

        // When - the normal admission path authenticates the player attachment.
        tracker.didAuthenticate(playerFull)
        let replay = RPGSharePlayController.journalAdmissionsForReplay(
            from: tracker.currentJournalMetadata()
        )

        // Then - one targeted Messenger stream can pin the master first and
        // subsequently admit the player's existing attachment through that
        // trusted relay. Both retain the attachment's original message ID.
        #expect(replay.count == 2)
        #expect(replay.first?.sender.isMaster == true)
        #expect(replay.map(\.messageID).contains(masterFull.messageID))
        #expect(replay.map(\.messageID).contains(playerFull.messageID))
        #expect(replay.allSatisfy { $0.isJournalAdmissionOnly })
        #expect(replay.allSatisfy { $0.journalPayloadDigest != nil })
    }

    @Test("Conflicting Journal metadata is rejected without poisoning the first admission")
    func conflictingPlayerJournalAdmissionStopsRoutingAndKeepsFirstFingerprint() async throws {
        // Given
        let env = try await NetworkStoreTestEnvironment.create()
        env.networkController.setupLocal()
        let participantID = UUID()
        let full = Self.playerFilePresentation(
            senderID: UUID(),
            messageID: UUID(),
            data: Data("photo".utf8)
        )
        let firstMetadata = try #require(
            RPGSharePlayController.playerJournalAdmissionMetadata(for: full)
        )
        var conflictingMetadata = firstMetadata
        conflictingMetadata.timestamp += 1

        // When
        await env.networkController.routeSharePlayUpdate(
            firstMetadata,
            id: participantID
        )
        await env.networkController.routeSharePlayUpdate(
            conflictingMetadata,
            id: participantID
        )

        // Then - neither control packet becomes a presentation or LAN event.
        #expect(env.masterDelegateSpy.calledReceived == 0)
        #expect(env.playerDelegateSpy.calledReceived == 0)
        #expect(env.masterNetworkSpy.sendResponseHistory.isEmpty)

        // When - the attachment matching the immutable first fingerprint arrives.
        await env.networkController.routeSharePlayFileUpdate(full)

        // Then - the conflict did not overwrite or invalidate the first admission.
        #expect(env.masterDelegateSpy.calledFileReceived == 1)
        let relayed = env.masterNetworkSpy.sendResponseHistory.compactMap {
            $0 as? GameNetworkModel
        }
        #expect(relayed.map { $0.data.data != nil } == [true])
    }

    @Test("SharePlay direct players cannot change identity or use local-only roles")
    func sharePlayPlayerTransportRoleAndIdentityArePinned() async throws {
        // Given
        let env = try await NetworkStoreTestEnvironment.create()
        let participantID = UUID()
        let first = Self.playerFilePresentation(
            senderID: UUID(),
            messageID: UUID(),
            data: nil
        )
        var rebound = first
        rebound.sender = GameSenderModel(
            id: UUID(),
            role: .player,
            name: "Copied player",
            characterId: nil
        )
        var observer = first
        observer.sender = GameSenderModel(
            id: UUID(),
            role: .observer,
            name: "Observer",
            characterId: nil
        )
        var proxy = first
        proxy.sender = GameSenderModel(
            id: UUID(),
            role: .proxy,
            name: "Proxy",
            characterId: nil
        )

        // When
        await env.networkController.routeSharePlayUpdate(first, id: participantID)
        await env.networkController.routeSharePlayUpdate(rebound, id: participantID)
        await env.networkController.routeSharePlayUpdate(observer, id: UUID())
        await env.networkController.routeSharePlayUpdate(proxy, id: UUID())

        // Then
        #expect(env.masterDelegateSpy.calledReceived == 1)
    }

    @Test("Trusted master participant can relay multiple immutable LAN player identities")
    func sharePlayMasterParticipantCanRelayLANPlayers() async {
        // Given
        let admission = SharePlayPlayerJournalAdmission()
        let masterParticipantID = UUID()
        let first = Self.playerFilePresentation(
            senderID: UUID(),
            messageID: UUID(),
            data: nil
        )
        let second = Self.playerFilePresentation(
            senderID: UUID(),
            messageID: UUID(),
            data: nil
        )

        // When / Then - a normal participant is immutable.
        #expect(await admission.acceptsPlayerMessenger(
            first,
            participantID: masterParticipantID
        ))
        #expect(!(await admission.acceptsPlayerMessenger(
            second,
            participantID: masterParticipantID
        )))

        // When / Then - after PlayerController authenticates this participant
        // as the master, the provisional direct binding is promoted to a relay.
        #expect(await admission.trustMasterRelay(participantID: masterParticipantID))
        #expect(await admission.acceptsPlayerMessenger(
            first,
            participantID: masterParticipantID
        ))
        #expect(await admission.acceptsPlayerMessenger(
            second,
            participantID: masterParticipantID
        ))
    }

    @Test("Journal message IDs are sender scoped")
    func sharePlayJournalAdmissionScopesSharedMessageIDBySender() async throws {
        // Given
        let admission = SharePlayPlayerJournalAdmission()
        let sharedMessageID = UUID()
        let firstParticipantID = UUID()
        let secondParticipantID = UUID()
        let first = Self.playerFilePresentation(
            senderID: UUID(),
            messageID: sharedMessageID,
            data: Data("first".utf8)
        )
        let second = Self.playerFilePresentation(
            senderID: UUID(),
            messageID: sharedMessageID,
            data: Data("second".utf8)
        )
        #expect(await admission.disposition(forJournal: first) == .deferred)
        #expect(await admission.disposition(forJournal: second) == .deferred)
        let firstMetadata = try #require(
            RPGSharePlayController.playerJournalAdmissionMetadata(for: first)
        )
        let secondMetadata = try #require(
            RPGSharePlayController.playerJournalAdmissionMetadata(for: second)
        )

        // When
        #expect(await admission.acceptsPlayerMessenger(
            firstMetadata,
            participantID: firstParticipantID
        ))
        let firstAdmission = await admission.admitAnnouncement(
            firstMetadata,
            participantID: firstParticipantID
        )
        guard case .admitted(let firstRelease) = firstAdmission else {
            Issue.record("Expected the first sender's Journal admission")
            return
        }

        // Then - admitting one sender does not release the other sender's UUID.
        #expect(firstRelease.map(\.model.sender.id) == [first.sender.id])
        #expect(await admission.disposition(forJournal: second) == .deferred)

        // When / Then
        #expect(await admission.acceptsPlayerMessenger(
            secondMetadata,
            participantID: secondParticipantID
        ))
        let secondAdmission = await admission.admitAnnouncement(
            secondMetadata,
            participantID: secondParticipantID
        )
        guard case .admitted(let secondRelease) = secondAdmission else {
            Issue.record("Expected the second sender's Journal admission")
            return
        }
        #expect(secondRelease.map(\.model.sender.id) == [second.sender.id])
    }

    @Test(
        "Pinned master metadata admits exact Journal payloads for every file flow",
        arguments: [
            NetworkModules.audio,
            .weather,
            .map,
            .photo,
            .pdf,
            .space
        ]
    )
    func sharePlayMasterJournalAdmissionRequiresPinnedExactMetadata(
        module: NetworkModules
    ) async throws {
        // Given
        let admission = SharePlayPlayerJournalAdmission()
        let masterParticipantID = UUID()
        let targetID: UUID? = (module == .audio || module == .weather) ? UUID() : nil
        let full = Self.masterJournalPresentation(
            masterID: UUID(),
            messageID: UUID(),
            module: module,
            targetID: targetID,
            data: Data("asset".utf8)
        )
        let metadata = try #require(
            RPGSharePlayController.masterJournalAdmissionMetadata(for: full)
        )
        var journalPayload = RPGSharePlayController.journalMetadata(for: full)
        journalPayload.data = NetworkCodableDataType(
            id: metadata.data.id,
            type: metadata.data.type,
            version: metadata.data.version,
            data: full.data.data,
            assetVersion: metadata.data.assetVersion,
            contentVersion: metadata.data.contentVersion
        )

        // When - Journal can race ahead, but unpinned Messenger metadata has no
        // authority to release it.
        #expect(await admission.disposition(forJournal: journalPayload) == .deferred)
        let unpinnedAdmission = await admission.admitAnnouncement(
            metadata,
            participantID: masterParticipantID
        )
        guard case .rejected = unpinnedAdmission else {
            Issue.record("Expected an unpinned master admission to be rejected")
            return
        }

        // When - PlayerController has pinned this physical master.
        #expect(await admission.trustMasterRelay(
            participantID: masterParticipantID
        ))
        let acceptedAdmission = await admission.admitAnnouncement(
            metadata,
            participantID: masterParticipantID
        )
        guard case .admitted(let release) = acceptedAdmission else {
            Issue.record("Expected the pinned master's Journal admission")
            return
        }

        // Then
        #expect(release.count == 1)
        #expect(release.first?.model.data.type == module)
        #expect(await admission.disposition(forJournal: journalPayload) == .authorized)
        if module == .audio {
            #expect(metadata.targetId == nil)
            #expect(metadata.type == .store)
        } else {
            #expect(metadata.targetId == targetID)
        }

        // And a copied message ID cannot authorize changed developer metadata.
        var forged = journalPayload
        forged.timestamp += 1
        #expect(await admission.disposition(forJournal: forged) == .rejected)
    }

    @Test(
        "SharePlay player presentation reaches LAN before master canonicalization",
        arguments: [NetworkModules.photo, .pdf, .space],
        SharePlayPlayerIngress.allCases
    )
    func sharePlayPlayerPresentationPreservesCanonicalLANOrdering(
        module: NetworkModules,
        ingress: SharePlayPlayerIngress
    ) async throws {
        // Given - the master-side handler represents the validation branch that
        // rejects a player's generation and immediately broadcasts canonical
        // master data. The network bridge must already have relayed the raw
        // player intent at that point.
        let env = try await NetworkStoreTestEnvironment.create()
        env.networkController.setupLocal()
        let masterId = UUID()
        let playerId = UUID()
        let itemId = UUID()
        let playerPresentation = GameNetworkModel(
            counter: 7,
            proxyCounter: 0,
            type: .reveal,
            subType: .show,
            masterId: masterId,
            sender: GameSenderModel(
                id: playerId,
                role: .player,
                name: "Player",
                characterId: nil
            ),
            audience: .group,
            purpose: .event,
            data: NetworkCodableDataType(
                id: itemId,
                type: module,
                version: 1,
                data: ingress == .journal ? Data("player payload".utf8) : nil
            )
        )
        let canonical = GameNetworkModel(
            counter: 50,
            proxyCounter: 0,
            type: .reveal,
            subType: .show,
            masterId: masterId,
            sender: GameSenderModel(
                id: masterId,
                role: .master,
                name: "Master",
                characterId: nil
            ),
            audience: .group,
            purpose: .event,
            data: NetworkCodableDataType(
                id: itemId,
                type: module,
                version: 2,
                data: Data("canonical".utf8)
            )
        )
        env.masterDelegateSpy.receivedHandler = { _, _ in
            if ingress == .messenger {
                env.masterNetworkSpy.sendResponse(data: canonical)
            }
        }
        env.masterDelegateSpy.receivedFileHandler = { _ in
            if ingress == .journal {
                env.masterNetworkSpy.sendResponse(data: canonical)
            }
        }

        // When
        switch ingress {
        case .messenger:
            await env.networkController.routeSharePlayUpdate(
                playerPresentation,
                id: UUID()
            )
        case .journal:
            let metadata = try #require(
                RPGSharePlayController.playerJournalAdmissionMetadata(
                    for: playerPresentation
                )
            )
            await env.networkController.routeSharePlayUpdate(
                metadata,
                id: UUID()
            )
            await env.networkController.routeSharePlayFileUpdate(playerPresentation)
        }

        // Then - LAN observes player intent first and authoritative correction
        // last, matching direct-LAN ingress and leaving the canonical item as
        // the final presentation.
        let relayed = env.masterNetworkSpy.sendResponseHistory.compactMap {
            $0 as? GameNetworkModel
        }
        #expect(relayed.map(\.sender.role) == [.player, .master])
        #expect(relayed.map(\.data.version) == [1, 2])
    }

    private static func deferredPeerGroupEvent(
        kind: DeferredPeerGroupEventKind,
        masterID: UUID,
        playerID: UUID,
        counter: Int
    ) -> GameNetworkModel {
        let subType: RPGMessageActionType
        let module: NetworkModules
        switch kind {
        case .mapPin:
            subType = .mapPin
            module = .map
        case .spaceTransform:
            subType = .spaceTransform
            module = .space
        case .dice:
            subType = .generic
            module = .dice
        }

        return GameNetworkModel(
            counter: counter,
            proxyCounter: 0,
            type: .update,
            subType: subType,
            masterId: masterID,
            sender: GameSenderModel(
                id: playerID,
                role: .player,
                name: "Peer",
                characterId: nil
            ),
            audience: .group,
            purpose: .event,
            data: NetworkCodableDataType(
                id: UUID(),
                type: module,
                version: 1,
                data: Data([UInt8(truncatingIfNeeded: counter)])
            )
        )
    }

    private static func rosterBroadcast(
        counter: Int,
        masterID: UUID,
        players: [PlayerGameModel]
    ) -> GameNetworkModel {
        GameNetworkModel(
            counter: counter,
            proxyCounter: 0,
            type: .update,
            subType: .ok,
            masterId: masterID,
            sender: GameSenderModel(
                id: masterID,
                role: .master,
                name: "Master",
                characterId: nil
            ),
            masterState: GameMasterStateModel(
                state: .started,
                adventureId: nil,
                adventureTitle: "Roster update",
                players: players,
                controls: [],
                features: GameFeatureModel()
            ),
            data: NetworkCodableDataType(
                id: UUID(),
                type: .setting,
                version: 0
            )
        )
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

    private static func playerFilePresentation(
        senderID: UUID,
        messageID: UUID,
        module: NetworkModules = .photo,
        data: Data?
    ) -> GameNetworkModel {
        GameNetworkModel(
            messageID: messageID,
            timestamp: 1_000,
            counter: 7,
            proxyCounter: 0,
            type: .reveal,
            subType: .show,
            masterId: messageID,
            sender: GameSenderModel(
                id: senderID,
                role: .player,
                name: "Player",
                characterId: nil
            ),
            audience: .group,
            purpose: .event,
            data: NetworkCodableDataType(
                id: messageID,
                type: module,
                version: 3,
                data: data,
                assetVersion: 4,
                contentVersion: 5
            )
        )
    }

    private static func masterJournalPresentation(
        masterID: UUID,
        messageID: UUID,
        module: NetworkModules = .photo,
        targetID: UUID? = nil,
        data: Data?
    ) -> GameNetworkModel {
        GameNetworkModel(
            messageID: messageID,
            timestamp: 2_000,
            counter: 11,
            proxyCounter: 0,
            type: .reveal,
            subType: .show,
            masterId: masterID,
            sender: GameSenderModel(
                id: masterID,
                role: .master,
                name: "Master",
                characterId: nil
            ),
            masterState: GameMasterStateModel(
                state: .started,
                adventureId: nil,
                adventureTitle: "Adventure",
                players: [],
                controls: [],
                features: GameFeatureModel()
            ),
            targetId: targetID,
            audience: targetID == nil ? .group : .target,
            purpose: .event,
            data: NetworkCodableDataType(
                id: messageID,
                type: module,
                version: 6,
                data: data,
                assetVersion: 7,
                contentVersion: 8
            )
        )
    }
}
#endif

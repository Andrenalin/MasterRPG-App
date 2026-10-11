// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import AdventureRPG
@testable import GameRPG
@testable import AudioRPG
@testable import CharacterRPG
@testable import PdfRPG
@testable import PhotoRPG
@testable import SpaceRPG
@testable import WeatherRPG

@Suite("Player fallback Bonjour role")
@MainActor
struct PlayerFallbackServiceTests {
    @Test("Direct and proxy players advertise the service their host browses")
    func fallbackServiceMatchesConnectionTopology() {
        // Given / When
        let direct = PlayerNetworkController(name: "Direct player")
        let proxy = PlayerNetworkController(name: "Proxy player", proxy: true)

        // Then
        #expect(direct.fallbackServiceType.serviceName == GameServiceType.master.serviceName)
        #expect(proxy.fallbackServiceType.serviceName == GameServiceType.proxyClient.serviceName)
    }
}

// MARK: - MasterControllerModel unit tests

@Suite("MasterControllerModel connection mapping")
@MainActor
struct MasterControllerModelConnectionTests {

}

// MARK: - GameMessagePipeline unit tests

@Suite("GameMessagePipeline")
struct GameMessagePipelineTests {

    @Test("duplicate non-ack message is ignored")
    func duplicateNonAckMessageIsIgnored() async {
        let pipeline = GameMessagePipeline()
        let message = Self.message(counter: 4, senderId: UUID())
        let event = GameMessageEvent(model: message, origin: .direct(UUID()))

        let first = await pipeline.enqueue(event)
        let duplicate = await pipeline.enqueue(GameMessageEvent(model: message, origin: .sharePlay(UUID())))

        #expect(first == .enqueued)
        #expect(duplicate == .duplicate)
    }

    @Test("same counter from different senders is accepted")
    func sameCounterFromDifferentSendersIsAccepted() async {
        let pipeline = GameMessagePipeline()
        let first = Self.message(counter: 8, senderId: UUID())
        let second = Self.message(counter: 8, senderId: UUID(), dataId: first.data.id)

        let firstQueued = await pipeline.enqueue(GameMessageEvent(model: first, origin: .direct(UUID())))
        let secondQueued = await pipeline.enqueue(GameMessageEvent(model: second, origin: .direct(UUID())))

        #expect(firstQueued == .enqueued)
        #expect(secondQueued == .enqueued)
    }

    @Test("counter zero messages are not deduplicated")
    func counterZeroMessagesAreNotDeduplicated() async {
        let pipeline = GameMessagePipeline()
        var message = Self.message(counter: 0, senderId: UUID())

        let first = await pipeline.enqueue(GameMessageEvent(model: message, origin: .direct(UUID())))
        let second = await pipeline.enqueue(GameMessageEvent(model: message, origin: .sharePlay(UUID())))

        #expect(first == .enqueued)
        #expect(second == .enqueued)
    }

    @Test("cancelled pipeline rejects new messages")
    func cancelledPipelineRejectsNewMessages() async {
        let pipeline = GameMessagePipeline()
        await pipeline.cancelAll()

        let queued = await pipeline.enqueue(GameMessageEvent(model: Self.message(counter: 1, senderId: UUID()), origin: .direct(UUID())))

        #expect(queued == .pipelineStopped)
    }

    @Test("queue-full rejection is distinct from a duplicate rejection")
    func queueFullRejectionIsDistinctFromDuplicate() async {
        let pipeline = GameMessagePipeline(maximumQueuedMessages: 2)
        let senderId = UUID()
        for counter in 1...2 {
            let result = await pipeline.enqueue(
                GameMessageEvent(model: Self.message(counter: counter, senderId: senderId), origin: .direct(UUID()))
            )
            #expect(result == .enqueued)
        }

        let overflow = await pipeline.enqueue(
            GameMessageEvent(model: Self.message(counter: 3, senderId: senderId), origin: .direct(UUID()))
        )

        #expect(overflow == .queueFull)
        #expect(overflow != .duplicate)
    }

    @Test("cancelling a drain in flight requeues the in-hand event instead of losing it")
    func requeueCurrentOnCancellationRestoresTheDequeuedEvent() async {
        let pipeline = GameMessagePipeline()
        let message = Self.message(counter: 9, senderId: UUID())
        let event = GameMessageEvent(model: message, origin: .direct(UUID()))
        #expect(await pipeline.enqueue(event) == .enqueued)

        let dequeued = await pipeline.next()
        #expect(dequeued != nil)

        await pipeline.requeueCurrentOnCancellation()

        let redelivered = await pipeline.next()
        #expect(redelivered?.model.counter == message.counter)
    }

    // CODE_AUDIT_21 §3.9: `reset()` cleared the busy flag while a handler of the old session was
    // still suspended, so the next enqueue started a second drain next to it.
    @Test("a reset while an event is in hand does not let a second drain start")
    func resetKeepsTheInFlightEventExclusive() async {
        let pipeline = GameMessagePipeline()
        let message = Self.message(counter: 1, senderId: UUID())
        let event = GameMessageEvent(model: message, origin: .direct(UUID()))
        #expect(await pipeline.enqueue(event) == .enqueued)
        #expect(await pipeline.next() != nil)

        await pipeline.reset()
        // The rejoined session replays the same message: the reset forgot its key.
        #expect(await pipeline.enqueue(event) == .enqueued)
        #expect(await pipeline.next() == nil)

        // The old session's handler returns. Its result is not recorded for the new session:
        // the replayed message is still pending, and is delivered to the one drain.
        await pipeline.processed(success: true)
        #expect(await pipeline.enqueue(event) == .duplicate)
        let replayed = await pipeline.next()
        #expect(replayed?.model.counter == message.counter)
        #expect(await pipeline.next() == nil)
    }

    @Test("an event of a reset session is not requeued into the new one")
    func staleEventIsNotRequeuedAfterReset() async {
        let pipeline = GameMessagePipeline()
        let event = GameMessageEvent(model: Self.message(counter: 2, senderId: UUID()), origin: .direct(UUID()))
        #expect(await pipeline.enqueue(event) == .enqueued)
        #expect(await pipeline.next() != nil)

        await pipeline.reset()
        await pipeline.requeueCurrentOnCancellation()

        #expect(await pipeline.hasQueuedMessages == false)
        #expect(await pipeline.next() == nil)
    }

    private static func message(counter: Int, senderId: UUID, dataId: UUID = UUID()) -> GameNetworkModel {
        let gameConfig = GameConfigModel(
            id: senderId,
            state: .started,
            master: MasterGameModel(id: UUID(), type: .master, name: "Master")
        )
        let data = NetworkCodableDataType(id: dataId, type: .photo, version: 1, data: nil)
        return GameNetworkModel(counter: counter, proxyCounter: 0, type: .reveal, subType: .show, gameConfig: gameConfig, data: data)
    }
}

// MARK: - MasterController lostPlayer integration tests

@Suite("MasterController lostPlayer")
@MainActor
struct MasterControllerLostPlayerTests {

    @Test("lostPlayer is a no-op when the connectionId is unknown")
    func lostPlayerNoOpForUnknownConnection() async throws {
        let env = try await ConnectionTestEnvironment.make()

        await env.master.lostPlayer(for: UUID())

        #expect(env.root.gameModel.gameRoster.players.isEmpty)
    }

    @Test("lostPlayer removes the player from the roster when their connectionId is known")
    func lostPlayerRemovesKnownPlayer() async throws {
        let env = try await ConnectionTestEnvironment.make()
        let connId = UUID()

        await env.master.receivedProcess(env.playerMessage, connectionId: connId)
        try #require(env.root.gameModel.gameRoster.players.count == 1)

        await env.master.lostPlayer(for: connId)

        #expect(env.root.gameModel.gameRoster.players.isEmpty)
    }

    @Test("lostPlayer removes only the departed player from audio availability reports")
    func lostPlayerPrunesDepartedPlayerFromAudioReports() async throws {
        // Given
        let env = try await ConnectionTestEnvironment.make()
        let departingConnectionId = UUID()
        let remainingConnectionId = UUID()
        let departingPlayerId = env.playerMessage.sender.id
        let remainingPlayerId = UUID()
        let remainingPlayerConfig = GameConfigModel(
            id: remainingPlayerId,
            state: .started,
            master: .empty
        )
        let remainingPlayerMessage = GameNetworkModel(
            counter: 0,
            proxyCounter: 0,
            type: .store,
            subType: .store,
            gameConfig: remainingPlayerConfig,
            gameRoster: GameRosterModel(players: [
                PlayerGameModel(id: remainingPlayerId, type: .player, name: "Remaining Player")
            ]),
            data: NetworkCodableDataType(id: UUID(), type: .setting, version: 0, data: nil)
        )
        await env.master.receivedProcess(env.playerMessage, connectionId: departingConnectionId)
        await env.master.receivedProcess(remainingPlayerMessage, connectionId: remainingConnectionId)

        let sharedAudioId = UUID()
        let departingOnlyAudioId = UUID()
        env.root.audioRoot.audioGameControllable.applyAudio(
            id: sharedAudioId,
            for: [departingPlayerId, remainingPlayerId]
        )
        env.root.audioRoot.audioGameControllable.applyAudio(
            id: departingOnlyAudioId,
            for: [departingPlayerId]
        )
        #expect(
            Set(env.root.audioRoot.gameControllable.gameModel.playerReport(for: sharedAudioId)) ==
                [departingPlayerId, remainingPlayerId]
        )

        // When
        await env.master.lostPlayer(for: departingConnectionId)

        // Then
        let audioReports = env.root.audioRoot.gameControllable.gameModel.playerReports
        #expect(audioReports.values.allSatisfy { !$0.contains(departingPlayerId) })
        #expect(audioReports[sharedAudioId]?.contains(remainingPlayerId) == true)
    }

    @Test("lostPlayer for the old connectionId does not remove a player who has already reconnected")
    func lostPlayerDoesNotRemoveReconnectedPlayer() async throws {
        let env = try await ConnectionTestEnvironment.make()
        let oldConnId = UUID()
        let newConnId = UUID()

        // Initial connection
        await env.master.receivedProcess(env.playerMessage, connectionId: oldConnId)
        try #require(env.root.gameModel.gameRoster.players.count == 1)

        // The live connection owns the identity until it is retired.
        await env.master.lostPlayer(for: oldConnId)

        // Player reconnects on a new connectionId.
        var reconnectMessage = env.playerMessage
        reconnectMessage.counter += 1
        await env.master.receivedProcess(reconnectMessage, connectionId: newConnId)
        try #require(env.root.gameModel.gameRoster.players.count == 1)

        // A duplicate late close event for the old connection must not evict
        // the player that is now bound to the new connection.
        await env.master.lostPlayer(for: oldConnId)

        #expect(
            env.root.gameModel.gameRoster.players.count == 1,
            "reconnected player must stay in the roster when the old connectionId fires lostPlayer"
        )
    }

    @Test("lostPlayer for new connectionId removes player after reconnect and second drop")
    func lostPlayerRemovesPlayerOnNewConnectionDrop() async throws {
        let env = try await ConnectionTestEnvironment.make()
        let oldConnId = UUID()
        let newConnId = UUID()

        await env.master.receivedProcess(env.playerMessage, connectionId: oldConnId)
        await env.master.lostPlayer(for: oldConnId)
        var reconnectMessage = env.playerMessage
        reconnectMessage.counter += 1
        await env.master.receivedProcess(reconnectMessage, connectionId: newConnId)
        try #require(env.root.gameModel.gameRoster.players.count == 1)

        // New connection also drops — player must be removed
        await env.master.lostPlayer(for: newConnId)

        #expect(env.root.gameModel.gameRoster.players.isEmpty)
    }
}

@Suite("MasterController direct and proxy paths")
@MainActor
struct MasterControllerDirectProxyTests {

    enum ObserverFilePresentationAttack: CaseIterable, Sendable {
        case photo
        case pdf
        case space
    }

    private static func transportMessage(
        role: GameType,
        senderID: UUID,
        masterID: UUID
    ) -> GameNetworkModel {
        GameNetworkModel(
            counter: 1,
            proxyCounter: 0,
            type: .store,
            subType: .store,
            masterId: masterID,
            sender: GameSenderModel(
                id: senderID,
                role: role,
                name: String(describing: role),
                characterId: nil
            ),
            data: NetworkCodableDataType(
                id: UUID(),
                type: .setting,
                version: 0
            )
        )
    }

    @Test("Master Space transform advances beyond retained peer time")
    func masterSpaceTransformUsesCausalTimestamp() async throws {
        let env = try await MasterControllerHarness.make(asProxy: false)
        let itemId = UUID()
        let version = 9
        let retainedTimestamp = Date.now.timeIntervalSince1970 + 60
        let retainedTransform = SpaceTransformModel(
            position: SIMD3<Float>(repeating: 0),
            scale: SIMD3<Float>(repeating: 1),
            rotation: SIMD4<Float>(0, 0, 0, 1)
        )
        let newTransform = SpaceTransformModel(
            position: SIMD3<Float>(1, 2, 3),
            scale: SIMD3<Float>(repeating: 2),
            rotation: SIMD4<Float>(0.5, 0.25, 0, 1)
        )
        #expect(env.root.spaceRoot.gameController.spaceGameModel.applyTransform(
            itemId: itemId,
            version: version,
            counter: 50_000,
            timestamp: retainedTimestamp,
            transform: retainedTransform
        ))
        let data = NetworkCodableDataType(
            id: itemId,
            type: .space,
            version: version,
            data: newTransform.encodeData()
        )

        await env.master.send(
            type: .update,
            subtype: .spaceTransform,
            updated: data
        )

        let outgoing = try #require(
            env.directMasterSpy.sendResponseData as? GameNetworkModel
        )
        let retained = try #require(
            env.root.spaceRoot.gameController.spaceGameModel.transformState(
                for: itemId,
                version: version
            )
        )
        #expect(outgoing.timestamp > retainedTimestamp)
        #expect(retained.timestamp == outgoing.timestamp)
        #expect(retained.counter == outgoing.counter)
        #expect(retained.transform == newTransform)
    }

    @Test("LAN rejects a remote master claim before relaying it")
    func lanRejectsRemoteMasterClaimBeforeRelay() async throws {
        // Given
        let env = try await MasterControllerHarness.make(asProxy: false)
        let connectionId = UUID()
        let attackerId = UUID()
        let expectedMasterId = env.root.gameModel.gameConfig.master.id
        let malicious = GameNetworkModel(
            counter: 91,
            proxyCounter: 0,
            type: .update,
            subType: .generic,
            masterId: expectedMasterId,
            sender: GameSenderModel(
                id: attackerId,
                role: .master,
                name: "Impostor",
                characterId: nil
            ),
            masterState: GameMasterStateModel(
                state: .started,
                adventureId: nil,
                adventureTitle: "Spoofed game",
                players: [],
                controls: [],
                features: GameFeatureModel()
            ),
            data: NetworkCodableDataType(
                id: UUID(),
                type: .dice,
                version: 1,
                data: Data([0x01])
            )
        )

        // When
        await env.root.networkStore.masterReceived(
            data: malicious.encodeData(),
            for: connectionId
        )

        // Then
        #expect(env.directMasterSpy.calledSendResponseExcept == 0)
        #expect(env.master.store.model.playerRoutes.playerId(for: connectionId) == nil)
        #expect(!env.root.gameModel.gameRoster.players.contains { $0.id == attackerId })
    }

    @Test("LAN rejects a player group event addressed to another master")
    func lanRejectsWrongMasterGroupEventBeforeRelay() async throws {
        // Given
        let env = try await MasterControllerHarness.make(asProxy: false)
        let connectionId = UUID()
        let playerId = UUID()
        let malicious = GameNetworkModel(
            counter: 92,
            proxyCounter: 0,
            type: .update,
            subType: .generic,
            masterId: UUID(),
            sender: GameSenderModel(
                id: playerId,
                role: .player,
                name: "Wrong session player",
                characterId: nil
            ),
            data: NetworkCodableDataType(
                id: UUID(),
                type: .dice,
                version: 1,
                data: Data([0x01])
            )
        )

        // When
        await env.root.networkStore.masterReceived(
            data: malicious.encodeData(),
            for: connectionId
        )

        // Then
        #expect(env.directMasterSpy.calledSendResponseExcept == 0)
        #expect(env.master.store.model.playerRoutes.playerId(for: connectionId) == nil)
        #expect(!env.root.gameModel.gameRoster.players.contains { $0.id == playerId })
    }

    @Test("An established physical origin cannot switch logical sender")
    func physicalOriginCannotSwitchSender() async throws {
        // Given
        let env = try await MasterControllerHarness.make(asProxy: false)
        let connectionId = UUID()
        let masterId = env.root.gameModel.gameConfig.master.id
        let firstPlayerId = UUID()
        let secondPlayerId = UUID()
        let first = GameNetworkModel(
            counter: 93,
            proxyCounter: 0,
            type: .store,
            subType: .store,
            masterId: masterId,
            sender: GameSenderModel(
                id: firstPlayerId,
                role: .player,
                name: "First player",
                characterId: nil
            ),
            data: NetworkCodableDataType(id: UUID(), type: .setting, version: 0)
        )
        var identitySwitch = first
        identitySwitch.counter = 94
        identitySwitch.sender = GameSenderModel(
            id: secondPlayerId,
            role: .player,
            name: "Second player",
            characterId: nil
        )

        // When
        await env.master.received(first, origin: .direct(connectionId))
        await env.master.received(identitySwitch, origin: .direct(connectionId))

        // Then
        #expect(env.master.store.model.playerRoutes.playerId(for: connectionId) == firstPlayerId)
        #expect(env.root.gameModel.gameRoster.players.contains { $0.id == firstPlayerId })
        #expect(!env.root.gameModel.gameRoster.players.contains { $0.id == secondPlayerId })
    }

    @Test("An observer connection cannot promote itself to player")
    func physicalOriginCannotSwitchRole() async throws {
        let env = try await MasterControllerHarness.make(asProxy: false)
        let connectionID = UUID()
        let observerID = UUID()
        let masterID = env.root.gameModel.gameConfig.master.id
        let bootstrap = GameNetworkModel(
            counter: 1,
            proxyCounter: 0,
            type: .store,
            subType: .store,
            masterId: masterID,
            sender: GameSenderModel(
                id: observerID,
                role: .observer,
                name: "Observer",
                characterId: nil
            ),
            data: NetworkCodableDataType(id: UUID(), type: .setting, version: 0)
        )
        var promoted = bootstrap
        promoted.counter = 2
        promoted.sender.role = .player

        await env.master.received(bootstrap, origin: .direct(connectionID))
        await env.master.received(promoted, origin: .direct(connectionID))

        let rosterPlayer = env.root.gameModel.gameRoster.players.first {
            $0.id == observerID
        }
        #expect(rosterPlayer?.type == .observer)
    }

    @Test("Main master accepts only roles supported by each transport")
    func mainMasterEnforcesTransportRoleMatrix() async throws {
        // Given
        let env = try await MasterControllerHarness.make(asProxy: false)
        let masterID = env.root.gameModel.gameConfig.master.id
        let fileObserverID = UUID()
        let fileProxyID = UUID()
        env.root.gameModel.gameRoster = GameRosterModel(players: [
            PlayerGameModel(id: fileObserverID, type: .observer, name: "File observer"),
            PlayerGameModel(id: fileProxyID, type: .proxy, name: "File proxy")
        ])

        // When / Then: Bonjour supports game players and observers.
        #expect(await env.master.accepts(
            Self.transportMessage(role: .player, senderID: UUID(), masterID: masterID),
            origin: .direct(UUID())
        ))
        #expect(await env.master.accepts(
            Self.transportMessage(role: .observer, senderID: UUID(), masterID: masterID),
            origin: .direct(UUID())
        ))
        #expect(!(await env.master.accepts(
            Self.transportMessage(role: .proxy, senderID: UUID(), masterID: masterID),
            origin: .direct(UUID())
        )))

        // When / Then: SharePlay Messenger and Journal are player-only.
        #expect(await env.master.accepts(
            Self.transportMessage(role: .player, senderID: UUID(), masterID: masterID),
            origin: .sharePlay(UUID())
        ))
        #expect(!(await env.master.accepts(
            Self.transportMessage(role: .observer, senderID: UUID(), masterID: masterID),
            origin: .sharePlay(UUID())
        )))
        #expect(!(await env.master.accepts(
            Self.transportMessage(role: .proxy, senderID: UUID(), masterID: masterID),
            origin: .sharePlay(UUID())
        )))
        // The Journal carries the file a player contributes.
        #expect(await env.master.accepts(
            Self.transportMessage(role: .player, senderID: UUID(), masterID: masterID),
            origin: .file
        ))
        #expect(!(await env.master.accepts(
            Self.transportMessage(role: .observer, senderID: fileObserverID, masterID: masterID),
            origin: .file
        )))
        #expect(!(await env.master.accepts(
            Self.transportMessage(role: .proxy, senderID: fileProxyID, masterID: masterID),
            origin: .file
        )))

        // A private proxy connection never enters the main master's ingress.
        #expect(!(await env.master.accepts(
            Self.transportMessage(role: .proxy, senderID: UUID(), masterID: masterID),
            origin: .proxy(UUID())
        )))
    }

    @Test("Proxy host accepts only proxy-role messages from its proxy transport")
    func proxyMasterEnforcesTransportRoleMatrix() async throws {
        // Given
        let env = try await MasterControllerHarness.make(asProxy: true)
        let masterID = env.root.gameModel.gameConfig.master.id

        // When / Then
        #expect(await env.master.accepts(
            Self.transportMessage(role: .proxy, senderID: UUID(), masterID: masterID),
            origin: .proxy(UUID())
        ))
        #expect(!(await env.master.accepts(
            Self.transportMessage(role: .player, senderID: UUID(), masterID: masterID),
            origin: .proxy(UUID())
        )))
        #expect(!(await env.master.accepts(
            Self.transportMessage(role: .observer, senderID: UUID(), masterID: masterID),
            origin: .proxy(UUID())
        )))
        #expect(!(await env.master.accepts(
            Self.transportMessage(role: .proxy, senderID: UUID(), masterID: masterID),
            origin: .direct(UUID())
        )))
        #expect(!(await env.master.accepts(
            Self.transportMessage(role: .proxy, senderID: UUID(), masterID: masterID),
            origin: .sharePlay(UUID())
        )))
        #expect(!(await env.master.accepts(
            Self.transportMessage(role: .proxy, senderID: UUID(), masterID: masterID),
            origin: .file
        )))
    }

    @Test("A disconnected proxy mirror can reconnect without changing the public player state")
    func proxyDisconnectReleasesOnlyItsPhysicalMapping() async throws {
        // Given
        let env = try await MasterControllerHarness.make(asProxy: true)
        let proxyID = UUID()
        let oldConnectionID = UUID()
        let newConnectionID = UUID()
        let audioID = UUID()
        let publicPlayer = PlayerGameModel(
            id: proxyID,
            type: .player,
            name: "Public host player"
        )
        env.root.gameModel.gameRoster = GameRosterModel(players: [publicPlayer])
        env.root.audioRoot.audioGameControllable.applyAudio(
            id: audioID,
            for: [proxyID]
        )
        var firstMessage = Self.transportMessage(
            role: .proxy,
            senderID: proxyID,
            masterID: env.root.gameModel.gameConfig.master.id
        )

        // When: the first physical mirror connects, then disappears.
        await env.root.networkProxyStore.masterReceived(
            data: firstMessage.encodeData(),
            for: oldConnectionID
        )
        #expect(env.master.store.model.playerRoutes.playerId(for: oldConnectionID) == proxyID)
        await env.root.networkProxyStore.masterLostPlayer(with: oldConnectionID)

        // Then: only the private connection binding is retired. The proxy is
        // invisible to public roster/report lifecycle and may reconnect under
        // a fresh physical connection ID.
        #expect(env.master.store.model.playerRoutes.playerId(for: oldConnectionID) == nil)
        #expect(env.root.gameModel.gameRoster.players.map(\.id) == [proxyID])
        #expect(
            env.root.audioRoot.gameControllable.gameModel
                .playerReport(for: audioID) == [proxyID]
        )

        firstMessage.counter += 1
        await env.root.networkProxyStore.masterReceived(
            data: firstMessage.encodeData(),
            for: newConnectionID
        )

        #expect(env.master.store.model.playerRoutes.playerId(for: newConnectionID) == proxyID)
        #expect(env.root.gameModel.gameRoster.players.map(\.id) == [proxyID])
    }

    @Test("Observer policy permits only passive data-less asset repairs")
    func observerPolicyPermitsOnlyPassiveRepairs() async throws {
        let env = try await MasterControllerHarness.make(asProxy: false)
        let observerId = UUID()
        let sender = GameSenderModel(
            id: observerId,
            role: .observer,
            name: "Observer",
            characterId: nil
        )
        let photoId = UUID()

        let legacyPhotoRepair = GameNetworkModel(
            counter: 1,
            proxyCounter: 0,
            type: .reveal,
            subType: .show,
            masterId: env.root.gameModel.gameConfig.id,
            sender: sender,
            data: NetworkCodableDataType(id: photoId, type: .photo, version: 3)
        )
        let normalized = try #require(env.master.normalizedObserverMessage(legacyPhotoRepair))
        #expect(normalized.isAssetRequest)
        #expect(normalized.data.data == nil)

        var uploadedPhoto = legacyPhotoRepair
        uploadedPhoto.data = NetworkCodableDataType(
            id: photoId,
            type: .photo,
            version: 3,
            data: Data("observer upload".utf8)
        )
        #expect(env.master.normalizedObserverMessage(uploadedPhoto) == nil)

        let disguisedAudioPlay = GameNetworkModel(
            counter: 2,
            proxyCounter: 0,
            type: .update,
            subType: .playAudio,
            masterId: env.root.gameModel.gameConfig.id,
            sender: sender,
            data: NetworkCodableDataType(id: UUID(), type: .audio, version: 1)
        )
        #expect(env.master.normalizedObserverMessage(disguisedAudioPlay) == nil)

        var mapContentRepair = disguisedAudioPlay
        mapContentRepair.type = .update
        mapContentRepair.subType = .generic
        mapContentRepair.data = NetworkCodableDataType(id: UUID(), type: .map, version: 1)
        #expect(env.master.normalizedObserverMessage(mapContentRepair) == nil)

        var disguisedMapPin = mapContentRepair
        disguisedMapPin.subType = .mapPin
        #expect(env.master.normalizedObserverMessage(disguisedMapPin) == nil)
    }

    @Test("Observer reports and screens require their exact protocol envelope")
    func observerReportAndScreenAllowlistUsesExactTuples() async throws {
        // Given
        let env = try await MasterControllerHarness.make(asProxy: false)
        let sender = GameSenderModel(
            id: UUID(),
            role: .observer,
            name: "Observer",
            characterId: nil
        )
        let masterId = env.root.gameModel.gameConfig.master.id
        let allowed = [
            GameNetworkModel(
                counter: 1,
                proxyCounter: 0,
                type: .update,
                subType: .audioList,
                masterId: masterId,
                sender: sender,
                data: NetworkCodableDataType(
                    id: UUID(),
                    type: .audio,
                    version: 0,
                    data: AudioListRequest(list: [], players: [:]).encodeData()
                )
            ),
            GameNetworkModel(
                counter: 2,
                proxyCounter: 0,
                type: .update,
                subType: .photoList,
                masterId: masterId,
                sender: sender,
                data: NetworkCodableDataType(
                    id: UUID(),
                    type: .photo,
                    version: 0,
                    data: PhotoListRequest(list: [:], players: [:]).encodeData()
                )
            ),
            GameNetworkModel(
                counter: 3,
                proxyCounter: 0,
                type: .update,
                subType: .pdfList,
                masterId: masterId,
                sender: sender,
                data: NetworkCodableDataType(
                    id: UUID(),
                    type: .pdf,
                    version: 0,
                    data: PdfListRequest(list: [:], players: [:]).encodeData()
                )
            ),
            GameNetworkModel(
                counter: 4,
                proxyCounter: 0,
                type: .update,
                subType: .spaceList,
                masterId: masterId,
                sender: sender,
                data: NetworkCodableDataType(
                    id: UUID(),
                    type: .space,
                    version: 0,
                    data: SpaceListRequest(list: [:], players: [:]).encodeData()
                )
            ),
            GameNetworkModel(
                counter: 5,
                proxyCounter: 0,
                type: .store,
                subType: .screen,
                masterId: masterId,
                sender: sender,
                data: NetworkCodableDataType(
                    id: UUID(),
                    type: .game,
                    version: 0,
                    data: Data([0x01])
                )
            )
        ]

        // When / Then - legitimate observer reports and screen samples remain accepted.
        for message in allowed {
            #expect(env.master.normalizedObserverMessage(message) != nil)
        }

        // When / Then - the same benign-looking actions cannot be paired with
        // a presentation type, a different module, or an absent payload.
        var revealList = allowed[1]
        revealList.type = .reveal
        #expect(env.master.normalizedObserverMessage(revealList) == nil)

        var mismatchedListModule = allowed[1]
        mismatchedListModule.data = NetworkCodableDataType(
            id: UUID(),
            type: .pdf,
            version: 0,
            data: PdfListRequest(list: [:], players: [:]).encodeData()
        )
        #expect(env.master.normalizedObserverMessage(mismatchedListModule) == nil)

        var revealScreen = allowed[4]
        revealScreen.type = .reveal
        #expect(env.master.normalizedObserverMessage(revealScreen) == nil)

        var dataLessScreen = allowed[4]
        dataLessScreen.data = NetworkCodableDataType(id: UUID(), type: .game, version: 0)
        #expect(env.master.normalizedObserverMessage(dataLessScreen) == nil)
    }

    @Test(
        "Malformed observer list or screen envelope cannot reveal a canonical file",
        arguments: ObserverFilePresentationAttack.allCases
    )
    func malformedObserverEnvelopeCannotRevealCanonicalFile(
        attack: ObserverFilePresentationAttack
    ) async throws {
        // Given
        let env = try await MasterControllerHarness.make(asProxy: false)
        let reference: NetworkCodableDataType
        let subType: RPGMessageActionType

        switch attack {
        case .photo:
            try await MockRoot.importTestData(
                into: env.root.adventureRoot,
                name: ResourcesDebug.photoTestData,
                itemCounter: 0
            )
            env.root.adventureRoot.startGame()
            let id = try #require(env.root.photoRoot.itemController.itemDataModel.items.first)
            reference = await env.root.photoRoot.gameControllable.share(id: id)
            subType = .photoList
        case .pdf:
            try await MockRoot.importTestData(
                into: env.root.adventureRoot,
                name: ResourcesDebug.pdfTestData,
                itemCounter: 0
            )
            env.root.adventureRoot.startGame()
            let id = try #require(env.root.pdfRoot.itemController.itemDataModel.items.first)
            reference = await env.root.pdfRoot.gameControllable.share(id: id)
            subType = .screen
        case .space:
            try await MockRoot.importTestData(
                into: env.root.adventureRoot,
                name: ResourcesDebug.spaceTestData,
                itemCounter: 0
            )
            env.root.adventureRoot.startGame()
            let id = try #require(env.root.spaceRoot.itemController.itemDataModel.items.first)
            reference = await env.root.spaceRoot.gameControllable.share(id: id)
            subType = .spaceList
        }

        let observerId = UUID()
        let observer = PlayerGameModel(id: observerId, type: .observer, name: "Observer")
        _ = env.root.gameModel.add(
            playerId: observerId,
            playerModel: observer,
            sharingModel: SharingControlModel(id: observerId, name: observer.name, show: true)
        )
        let malicious = GameNetworkModel(
            counter: 41,
            proxyCounter: 0,
            type: .reveal,
            subType: subType,
            masterId: env.root.gameModel.gameConfig.master.id,
            sender: GameSenderModel(
                id: observerId,
                role: .observer,
                name: observer.name,
                characterId: nil
            ),
            data: NetworkCodableDataType(
                id: reference.id,
                type: reference.type,
                version: reference.version,
                assetVersion: reference.assetVersion,
                contentVersion: reference.contentVersion
            )
        )
        let sendCount = env.directMasterSpy.sendResponseHistory.count

        // When
        await env.master.received(malicious, connectionId: UUID())

        // Then
        #expect(env.directMasterSpy.sendResponseHistory.count == sendCount)
    }

    @Test("Observer cannot trigger audio play even when labelling it an asset request")
    func observerCannotTriggerAudioPlay() async throws {
        let env = try await MasterControllerHarness.make(asProxy: false)
        let observerId = UUID()
        _ = env.root.gameModel.add(
            playerId: observerId,
            playerModel: PlayerGameModel(id: observerId, type: .observer, name: "Observer"),
            sharingModel: SharingControlModel(id: observerId, name: "Observer", show: true)
        )
        let audioId = UUID()
        let malicious = GameNetworkModel(
            counter: 7,
            proxyCounter: 0,
            type: .update,
            subType: .playAudio,
            masterId: env.root.gameModel.gameConfig.id,
            sender: GameSenderModel(
                id: observerId,
                role: .observer,
                name: "Observer",
                characterId: nil
            ),
            data: NetworkCodableDataType(id: audioId, type: .audio, version: 1)
        )
        let sendCount = env.directMasterSpy.sendResponseHistory.count

        await env.master.received(malicious, connectionId: UUID())

        #expect(env.master.gameModel.pendingAudioPlays[audioId] == nil)
        #expect(env.directMasterSpy.sendResponseHistory.count == sendCount)
    }

    @Test("start, stop, and send use the injected network stores")
    func startStopAndSendUseNetworkStores() async throws {
        let env = try await MasterControllerHarness.make(asProxy: false, directStreaming: true)
        let playerId = UUID()
        let hiddenPlayerId = UUID()
        env.root.gameModel.gameRoster = GameRosterModel(
            players: [
                PlayerGameModel(id: playerId, type: .player, name: "Visible"),
                PlayerGameModel(id: hiddenPlayerId, type: .observer, name: "Hidden")
            ]
        )
        env.root.gameModel.gameControl = GameControlModel(
            controls: [
                SharingControlModel(id: playerId, name: "Visible", show: true),
                SharingControlModel(id: hiddenPlayerId, name: "Hidden", show: false)
            ]
        )
        let data = NetworkCodableDataType(id: UUID(), type: .photo, version: 1, data: nil)

        await env.master.start()
        await env.master.send(updated: data)
        await env.master.game(message: data, actionType: .generic, playerId: playerId)
        await env.master.stop()

        #expect(env.directMasterSpy.calledStartStreaming == 1)
        #expect(env.proxyMasterSpy.calledStartProxyStreaming == 0)
        #expect(env.directMasterSpy.calledSendResponseAll == 2)
        #expect(env.directMasterSpy.calledStopStreaming == 1)
        #expect(env.directPlayerSpy.calledStop == 1)
        #expect(env.root.gameModel.gameRoster.players.isEmpty)
        #expect(env.root.gameModel.gameControl.controls.isEmpty)

        let filteredMessage = try #require(env.directMasterSpy.sendResponseData as? GameNetworkModel)
        // Targeting replaced the controls filter: the message is addressed to
        // the player, the master state stays complete.
        #expect(filteredMessage.targetId == playerId)
        #expect(filteredMessage.masterState?.controls.map(\.id) == [playerId, hiddenPlayerId])
    }

    @Test("direct receive, ready, and file receive process messages")
    func directReceiveAndFileReceiveProcessMessages() async throws {
        let env = try await MasterControllerHarness.make(asProxy: false)
        let connectionId = UUID()
        let playerId = UUID()
        let playerConfig = GameConfigModel(id: playerId, state: .started, master: .empty)
        let playerRoster = GameRosterModel(players: [PlayerGameModel(id: playerId, type: .player, name: "Player")])
        let data = NetworkCodableDataType(id: UUID(), type: .setting, version: 0, data: nil)
        let message = GameNetworkModel(
            counter: 5,
            proxyCounter: 0,
            type: .store,
            subType: .store,
            gameConfig: playerConfig,
            gameRoster: playerRoster,
            data: data
        )

        await env.master.ready(for: connectionId)
        await env.master.received(message, connectionId: connectionId)
        await env.master.receivedFile(GameNetworkModel(
            counter: 6,
            proxyCounter: 0,
            type: .store,
            subType: .store,
            gameConfig: playerConfig,
            gameRoster: playerRoster,
            data: data
        ))
        await env.master.receivedFile(GameNetworkModel(
            counter: 7,
            proxyCounter: 0,
            type: .store,
            subType: .store,
            gameConfig: env.root.gameModel.gameConfig,
            gameRoster: playerRoster,
            data: data
        ))

        #expect(env.root.gameModel.gameRoster.players.map(\.id) == [playerId])
        #expect(env.master.store.model.playerRoutes.playerId(for: connectionId) == playerId)
    }

    @Test("proxy ready sends the selected character to a connection")
    func proxyReadySendsSelectedCharacter() async throws {
        let env = try await MasterControllerHarness.make(asProxy: true)
        let characterId = await env.root.characterRoot.itemController.addNew(type: .character)
        env.root.characterRoot.editController.reset(name: "Proxy Hero", itemId: characterId)
        let playerId = env.root.gameModel.gameConfig.id
        env.root.gameModel.gameRoster = GameRosterModel(players: [
            PlayerGameModel(id: playerId, type: .proxy, name: "Proxy", characterId: characterId)
        ])

        let connectionId = UUID()
        await env.master.readyProxy(for: connectionId)

        let sent = try #require(env.proxyMasterSpy.sendResponseData as? GameNetworkModel)
        #expect(env.proxyMasterSpy.calledSendResponseId == 1)
        #expect(sent.data.type == .value)
        #expect(sent.data.id == characterId)
    }

    @Test("proxy messages are never relayed raw to the master network")
    func proxyMessageIsNotRelayedRawToMaster() async throws {
        let env = try await MasterControllerHarness.make(asProxy: true)
        let playerId = UUID()
        let playerConfig = GameConfigModel(id: playerId, state: .started, master: .empty)
        let message = GameNetworkModel(
            counter: 9,
            proxyCounter: 1,
            type: .store,
            subType: .store,
            gameConfig: playerConfig,
            gameRoster: GameRosterModel(players: [PlayerGameModel(id: playerId, type: .player, name: "Remote")]),
            data: NetworkCodableDataType(id: UUID(), type: .photo, version: 1, data: nil)
        )

        await env.master.receivedServerProxy(message, connectionId: UUID())

        // The proxy stays invisible: nothing goes upstream with its identity,
        // and it never enters the host's roster.
        #expect(env.directPlayerSpy.calledRequest == 0)
        #expect(env.root.gameModel.gameRoster.players.isEmpty)
    }

    @Test("weather handler covers report/reveal; game handler is a harmless no-op")
    func weatherAndGameHandlers() async throws {
        let env = try await MasterControllerHarness.make(asProxy: false)
        let weatherId = await env.root.weatherRoot.itemController.addNew(type: .scenario)
        env.root.weatherRoot.editController.reset(name: "Storm", itemId: weatherId)
        let playerConfig = GameConfigModel(id: UUID(), state: .started, master: .empty)
        let weatherData = try await env.root.weatherRoot.gameControllable.createGameData(for: weatherId)

        let reveal = GameNetworkModel(counter: 11, proxyCounter: 0, type: .reveal, subType: .show, gameConfig: playerConfig, data: weatherData)
        let revealed = try await env.master.handle(reveal)
        #expect(revealed?.id == weatherId)
        #expect(revealed?.type == .weather)

        let ok = GameNetworkModel(counter: 12, proxyCounter: 0, type: .update, subType: .ok, gameConfig: playerConfig, data: weatherData)
        let okResult = try await env.master.handle(ok)
        #expect(okResult == nil)

        // `.game`-typed envelopes are a legacy no-op dispatch target (the
        // player-screenshot-sharing feature they carried was removed as dead
        // code — see CODE_AUDIT_Game §9.17); this just confirms the dispatch
        // case still exists and is harmless.
        let gameMessage = GameNetworkModel(
            counter: 13,
            proxyCounter: 0,
            type: .update,
            subType: .generic,
            gameConfig: playerConfig,
            data: NetworkCodableDataType(id: UUID(), type: .game, version: 1, data: Data("screen".utf8))
        )
        let gameResult = try await env.master.handle(gameMessage)
        #expect(gameResult == nil)
    }
}

// MARK: - Test environment

private struct ConnectionTestEnvironment {
    let master: MasterController
    let root: GameRoot
    let playerMessage: GameNetworkModel

    static func make() async throws -> ConnectionTestEnvironment {
        let root = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: root.adventureRoot)
        try await MockRoot.resetGameController(for: root)

        let masterId = UUID()
        let masterConfig = GameConfigModel(
            id: masterId,
            state: .started,
            master: MasterGameModel(id: masterId, type: .master, name: "TestMaster")
        )
        await root.gameModel.reset(gameConfig: masterConfig)
        let master = await MasterController(root: root, asProxy: false)

        let playerId = UUID()
        let playerConfig = GameConfigModel(id: playerId, state: .started, master: .empty)
        let playerRoster = GameRosterModel(
            players: [PlayerGameModel(id: playerId, type: .player, name: "TestPlayer")]
        )
        let playerMessage = GameNetworkModel(
            counter: 0,
            proxyCounter: 0,
            type: .store,
            subType: .store,
            gameConfig: playerConfig,
            gameRoster: playerRoster,
            data: NetworkCodableDataType(id: UUID(), type: .setting, version: 0, data: nil)
        )

        return ConnectionTestEnvironment(master: master, root: root, playerMessage: playerMessage)
    }
}

@MainActor
private struct MasterControllerHarness {
    let root: GameRoot
    let master: MasterController
    let directMasterSpy: MasterNetworkControllableMock
    let proxyMasterSpy: MasterNetworkControllableMock
    let directPlayerSpy: PlayerStoreAbstractionMock
    let proxyPlayerSpy: PlayerStoreAbstractionMock

    static func make(asProxy: Bool, directStreaming: Bool = false) async throws -> MasterControllerHarness {
        let root = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: root.adventureRoot)
        try await MockRoot.resetGameController(for: root)

        let directMasterModel = MasterNetworkModel(name: "DirectMaster")
        directMasterModel.isStreaming = directStreaming
        let proxyMasterModel = MasterNetworkModel(name: "ProxyMaster")
        let directMasterSpy = MasterNetworkControllableMock(networkModel: directMasterModel)
        let proxyMasterSpy = MasterNetworkControllableMock(networkModel: proxyMasterModel)
        let directPlayerSpy = PlayerStoreAbstractionMock()
        let proxyPlayerSpy = PlayerStoreAbstractionMock()

        let directNetwork = GameNetworkController(
            name: "Direct",
            proxy: false,
            masterBuilder: { _, _ in directMasterSpy },
            playerBuilder: { _, _ in directPlayerSpy }
        )
        let proxyNetwork = GameNetworkController(
            name: "Proxy",
            proxy: true,
            masterBuilder: { _, _ in proxyMasterSpy },
            playerBuilder: { _, _ in proxyPlayerSpy }
        )

        root.networkStore = directNetwork
        root.networkProxyStore = proxyNetwork

        let masterId = UUID()
        let masterModel = MasterGameModel(id: masterId, type: .master, name: "Master", adventureId: UUID(), adventureTitle: "Adventure")
        root.gameModel.reset(gameConfig: GameConfigModel(id: masterId, state: .started, master: masterModel))
        let master = MasterController(root: root, asProxy: asProxy)

        return MasterControllerHarness(
            root: root,
            master: master,
            directMasterSpy: directMasterSpy,
            proxyMasterSpy: proxyMasterSpy,
            directPlayerSpy: directPlayerSpy,
            proxyPlayerSpy: proxyPlayerSpy
        )
    }
}

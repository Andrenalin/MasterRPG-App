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
    static func create() async throws -> NetworkStoreTestEnvironment {
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
        networkController.model.setMasterDelegate(masterDelegateSpy)
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
        await env.networkController.startMasterGame(game: .master, titleImage: nil)
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

        // Then - The master-side delegates may serve it, but another player's
        // controller must never receive it as a presentation.
        #expect(sharePlayPeer.masterDelegateSpy.calledReceived == 1)
        #expect(sharePlayPeer.masterDelegateSpy.calledFileReceived == 1)
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
        let result = await env.networkController.startPlayerGame(to: nil)
        #expect(result == false)
        #expect(env.playerNetworkSpy.calledToggleConnection == 0)

        // Act & Assert - Start player game with device (should succeed)
        let connectResult = await env.networkController.startPlayerGame(
            to: BrowserGameModel(id: UUID(), endpointName: "MasterTestDevice", connectionMode: .observer)
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

    @Test("SharePlay file routing completes before returning to the journal")
    func sharePlayFileRoutingCompletesBeforeReturningToJournal() async throws {
        let env = try await NetworkStoreTestEnvironment.create()

        await env.networkController.handleFileUpdate(masterGameNetworkModel)

        #expect(env.playerDelegateSpy.calledFileReceived == 1)
    }

    @Test("SharePlay attachment failure routing completes before returning to the journal")
    func sharePlayAttachmentFailureRoutingCompletesBeforeReturningToJournal() async throws {
        let env = try await NetworkStoreTestEnvironment.create()

        await env.networkController.handleFileLoadFailure(masterGameNetworkModel)

        #expect(env.playerDelegateSpy.calledFileLoadFailed == 1)
        #expect(env.playerDelegateSpy.calledFileReceived == 0)
    }

    @Test("SharePlay messenger routing completes before receiving the next message")
    func sharePlayMessengerRoutingCompletesBeforeReceivingNextMessage() async throws {
        let env = try await NetworkStoreTestEnvironment.create()

        await env.networkController.handleUpdate(masterGameNetworkModel, id: UUID())

        #expect(env.playerDelegateSpy.calledReceived == 1)
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
                version: 1
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
            env.masterNetworkSpy.sendResponse(data: canonical)
        }
        env.masterDelegateSpy.receivedFileHandler = { _ in
            env.masterNetworkSpy.sendResponse(data: canonical)
        }

        // When
        switch ingress {
        case .messenger:
            await env.networkController.routeSharePlayUpdate(
                playerPresentation,
                id: UUID()
            )
        case .journal:
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

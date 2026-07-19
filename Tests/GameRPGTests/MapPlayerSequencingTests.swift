// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import AdventureRPG
@testable import GameRPG
@testable import MapRPG
@testable import PhotoRPG

@Suite("Map player message sequencing", .serialized)
@MainActor
final class MapPlayerSequencingTests {
    private var masterRoot: GameRoot!
    private var playerRoot: GameRoot!
    private var playerController: PlayerController!
    private var networkController: GameNetworkController!
    private var playerNetworkSpy: PlayerStoreAbstractionMock!

    private func setUp() async throws {
        // Given a master with imported Map data and a connected, empty player.
        let masterId = UUID()
        let master = MasterGameModel(
            id: masterId,
            type: .master,
            name: "Map Master"
        )

        masterRoot = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: masterRoot.adventureRoot)
        try await MockRoot.resetGameController(for: masterRoot)
        masterRoot.gameModel.reset(
            gameConfig: GameConfigModel(
                id: masterId,
                state: .started,
                master: master
            )
        )
        try await MockRoot.importTestData(into: masterRoot.adventureRoot)
        masterRoot.adventureRoot.startGame()

        let masterNetworkSpy = MasterNetworkControllableMock()
        let playerNetworkSpy = PlayerStoreAbstractionMock()
        self.playerNetworkSpy = playerNetworkSpy
        networkController = GameNetworkController(
            name: "Map Player Test",
            proxy: false,
            masterBuilder: { _, _ in masterNetworkSpy },
            playerBuilder: { _, _ in playerNetworkSpy }
        )

        playerRoot = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: playerRoot.adventureRoot)
        try await MockRoot.resetGameController(for: playerRoot)
        let playerId = UUID()
        playerRoot.gameModel.reset(
            gameConfig: GameConfigModel(
                id: playerId,
                state: .started,
                master: master
            ),
            gameRoster: GameRosterModel(
                players: [
                    PlayerGameModel(
                        id: playerId,
                        type: .player,
                        name: "Map Player"
                    )
                ]
            )
        )
        playerRoot.networkStore = networkController
        playerRoot.adventureRoot.startGame()
        playerController = PlayerController(root: playerRoot, asGameMaster: false)
        networkController.model.setPlayerDelegate(playerController)
    }

    private func initialMapMessage(
        counter: Int = 10
    ) async throws -> (itemId: UUID, message: GameNetworkModel) {
        let itemId = try #require(masterRoot.mapRoot.itemController.itemDataModel.items.first)
        let data = try await masterRoot.mapRoot.mapGameControllable.createMapGameData(for: itemId)
        let message = masterRoot.gameModel.outgoingMessage(
            counter: counter,
            type: .reveal,
            subType: .show,
            asMaster: true,
            data: data
        )
        return (itemId, message)
    }

    @Test("A background repair is bounded by the Map generation, not the message counter")
    func mapBackgroundRepairCoalescesNewerCounters() throws {
        // Given
        let model = PlayerControllerModel()
        let itemId = UUID()

        // When
        let firstRequest = model.beginMapBackgroundRepair(
            itemId: itemId,
            assetVersion: 17,
            contentVersion: 23,
            presentsMap: true,
            counter: 40
        )
        let duplicateRequest = model.beginMapBackgroundRepair(
            itemId: itemId,
            assetVersion: 17,
            contentVersion: 23,
            presentsMap: false,
            counter: 41
        )

        // Then
        #expect(firstRequest)
        #expect(!duplicateRequest)
        let pending = try #require(model.pendingMapRepairRequirement(itemId: itemId))
        #expect(pending.presentsMap)
        #expect(pending.counter == 41)
    }

    @Test("An older Map state cannot roll live state backward")
    func staleMapStateIsIgnored() async throws {
        // Given
        try await setUp()
        let initial = try await initialMapMessage()
        _ = try #require(try await playerController.handleMap(initial.message))
        let masterMap = masterRoot.mapRoot.gameController.gameItem(for: initial.itemId)
        let entryId = try #require(masterMap.entries.first?.id)

        masterMap[entryId].isShown = true
        let newer = masterRoot.gameModel.outgoingMessage(
            counter: 30,
            type: .update,
            subType: .mapState,
            asMaster: true,
            data: masterRoot.mapRoot.mapGameControllable.networkMapUpdate(for: initial.itemId)
        )
        masterMap[entryId].isShown = false
        let older = masterRoot.gameModel.outgoingMessage(
            counter: 29,
            type: .update,
            subType: .mapState,
            asMaster: true,
            data: masterRoot.mapRoot.mapGameControllable.networkMapUpdate(for: initial.itemId)
        )

        // When
        _ = try await playerController.handleMap(newer)
        _ = try await playerController.handleMap(older)

        // Then
        let playerMap = playerRoot.mapRoot.gameController.gameItem(for: initial.itemId)
        #expect(playerMap[entryId].isShown)
    }

    @Test("A player applies peer Map-pin group events and retains the newest pin timestamp")
    func peerMapPinGroupEventUsesPinTimestamp() async throws {
        // Given: the master package establishes one Map generation containing
        // a peer-owned player pin.
        try await setUp()
        let itemId = try #require(masterRoot.mapRoot.itemController.itemDataModel.items.first)
        let peerId = UUID()
        let masterMap = masterRoot.mapRoot.gameController.gameItem(for: itemId)
        let initialPin = MapPinModel(
            id: peerId,
            name: "Peer pin",
            location: CGPoint(x: 1, y: 2),
            isPlayer: true,
            players: [peerId],
            timeInterval: 10
        )
        masterMap.mapPins.append(initialPin)
        let fullMap = try await masterRoot.mapRoot.mapGameControllable.createMapGameData(
            for: itemId
        )
        let reveal = masterRoot.gameModel.outgoingMessage(
            counter: 30,
            type: .reveal,
            subType: .show,
            asMaster: true,
            data: fullMap
        )
        _ = try #require(try await playerController.handleMap(reveal))

        func event(counter: Int, pin: MapPinModel) -> GameNetworkModel {
            GameNetworkModel(
                counter: counter,
                proxyCounter: 0,
                type: .update,
                subType: .mapPin,
                masterId: reveal.masterId,
                sender: GameSenderModel(
                    id: peerId,
                    role: .player,
                    name: "Peer",
                    characterId: nil
                ),
                data: NetworkCodableDataType(
                    id: itemId,
                    type: .map,
                    version: fullMap.version,
                    data: pin.encodeData(),
                    assetVersion: fullMap.assetVersion,
                    contentVersion: fullMap.contentVersion
                )
            )
        }

        // When: a peer's current group event arrives.
        var currentPin = initialPin
        currentPin.location = CGPoint(x: 5, y: 6)
        currentPin.timeInterval = 20
        let currentEvent = event(counter: 40, pin: currentPin)
        #expect(currentEvent.effectiveAudience == .group)
        let response = try await playerController.handleMap(currentEvent)

        // Then: the receiver applies it directly and sends no response.
        #expect(response == nil)
        let playerMap = playerRoot.mapRoot.gameController.gameItem(for: itemId)
        #expect(playerMap.mapPins.first { $0.id == peerId }?.location == currentPin.location)

        // When: a later delivery carries an older pin timestamp.
        var stalePin = currentPin
        stalePin.location = CGPoint(x: 9, y: 10)
        stalePin.timeInterval = 15
        _ = try await playerController.handleMap(event(counter: 41, pin: stalePin))

        // Then: timestamp ordering prevents the delayed event from rolling the
        // peer pin backward.
        let retainedPin = try #require(playerMap.mapPins.first { $0.id == peerId })
        #expect(retainedPin.location == currentPin.location)
        #expect(retainedPin.timeInterval == currentPin.timeInterval)
    }

    @Test("A peer Map-pin event waits for its Map generation and still keeps the newest timestamp")
    func peerMapPinBeforeMapGenerationIsRetried() async throws {
        // Given: a Map package and a peer-owned pin have not reached the player
        // yet, but the peer's small group events overtake that package.
        try await setUp()
        let itemId = try #require(masterRoot.mapRoot.itemController.itemDataModel.items.first)
        let peerId = UUID()
        let masterMap = masterRoot.mapRoot.gameController.gameItem(for: itemId)
        let initialPin = MapPinModel(
            id: peerId,
            name: "Peer pin",
            location: CGPoint(x: 1, y: 2),
            isPlayer: true,
            players: [peerId],
            timeInterval: 10
        )
        masterMap.mapPins.append(initialPin)
        let fullMap = try await masterRoot.mapRoot.mapGameControllable.createMapGameData(for: itemId)
        let reveal = masterRoot.gameModel.outgoingMessage(
            counter: 30,
            type: .reveal,
            subType: .show,
            asMaster: true,
            data: fullMap
        )

        func event(counter: Int, pin: MapPinModel) -> GameNetworkModel {
            GameNetworkModel(
                counter: counter,
                proxyCounter: 0,
                type: .update,
                subType: .mapPin,
                masterId: reveal.masterId,
                sender: GameSenderModel(
                    id: peerId,
                    role: .player,
                    name: "Peer",
                    characterId: nil
                ),
                data: NetworkCodableDataType(
                    id: itemId,
                    type: .map,
                    version: fullMap.version,
                    data: pin.encodeData(),
                    assetVersion: fullMap.assetVersion,
                    contentVersion: fullMap.contentVersion
                )
            )
        }

        var newestPin = initialPin
        newestPin.location = CGPoint(x: 7, y: 8)
        newestPin.timeInterval = 30
        var delayedOlderPin = newestPin
        delayedOlderPin.location = CGPoint(x: 4, y: 5)
        delayedOlderPin.timeInterval = 20

        // When: the newest event and then an older duplicate arrive before the
        // Journal-backed full Map.
        #expect(try await playerController.handleMap(event(counter: 40, pin: newestPin)) == nil)
        #expect(try await playerController.handleMap(event(counter: 41, pin: delayedOlderPin)) == nil)

        // And the package later establishes the advertised generation.
        _ = try #require(try await playerController.handleMap(reveal))

        // Then: deferred replay applies only the newest pin intent.
        let playerMap = playerRoot.mapRoot.gameController.gameItem(for: itemId)
        let retainedPin = try #require(playerMap.mapPins.first { $0.id == peerId })
        #expect(retainedPin.location == newestPin.location)
        #expect(retainedPin.timeInterval == newestPin.timeInterval)
    }

    @Test("Malformed high-counter state does not reserve the sequence")
    func malformedMapStateDoesNotBlockValidState() async throws {
        // Given
        try await setUp()
        let initial = try await initialMapMessage()
        _ = try #require(try await playerController.handleMap(initial.message))
        let masterMap = masterRoot.mapRoot.gameController.gameItem(for: initial.itemId)
        let entryId = try #require(masterMap.entries.first?.id)
        masterMap[entryId].isShown = true
        let validData = masterRoot.mapRoot.mapGameControllable.networkMapUpdate(for: initial.itemId)
        let valid = masterRoot.gameModel.outgoingMessage(
            counter: 49,
            type: .update,
            subType: .mapState,
            asMaster: true,
            data: validData
        )
        let malformed = masterRoot.gameModel.outgoingMessage(
            counter: 50,
            type: .update,
            subType: .mapState,
            asMaster: true,
            data: NetworkCodableDataType(
                id: initial.itemId,
                type: .map,
                version: validData.version,
                data: "\(entryId)|[]".data(using: .utf8),
                assetVersion: validData.assetVersion,
                contentVersion: validData.contentVersion
            )
        )

        // When
        let malformedResponse = try await playerController.handleMap(malformed)
        _ = try await playerController.handleMap(valid)

        // Then
        #expect(malformedResponse == nil)
        let playerMap = playerRoot.mapRoot.gameController.gameItem(for: initial.itemId)
        #expect(playerMap[entryId].isShown)
    }

    @Test("A state with stale structure requests only content and resumes after it arrives")
    func mapStateRequestsStructuralRepairWithoutFullMap() async throws {
        // Given
        try await setUp()
        let initial = try await initialMapMessage()
        _ = try #require(try await playerController.handleMap(initial.message))
        let masterMap = masterRoot.mapRoot.gameController.gameItem(for: initial.itemId)
        let entryId = try #require(masterMap.entries.first?.id)
        masterMap.name = "Changed structure"
        masterMap[entryId].isShown = true
        let state = masterRoot.gameModel.outgoingMessage(
            counter: 30,
            type: .update,
            subType: .mapState,
            asMaster: true,
            data: masterRoot.mapRoot.mapGameControllable.networkMapUpdate(for: initial.itemId)
        )
        playerController.gameModel.gameUpdateType = .none

        // When the state references a newer structural baseline.
        let request = try #require(try await playerController.handleMap(state))

        // Then only the photo-free content snapshot is requested, with the
        // exact proxy-safe versions and no bytes uploaded by the player.
        #expect(request.type == .update)
        #expect(request.subType == .generic)
        #expect(request.purpose == .assetRequest)
        #expect(request.effectiveAudience == .master)
        #expect(request.data.data == nil)
        #expect(request.data.assetVersion == state.data.assetVersion)
        #expect(request.data.contentVersion == state.data.contentVersion)
        #expect(playerController.gameModel.pendingMapRequests.contains(initial.itemId))
        #expect(playerController.gameModel.gameUpdateType == .none)

        let duplicateRequest = try await playerController.handleMap(state)
        #expect(duplicateRequest == nil)

        let structuralData = await masterRoot.mapRoot.mapGameControllable.networkMapContentUpdate(
            for: initial.itemId
        )
        let structuralResponse = masterRoot.gameModel.outgoingMessage(
            counter: 31,
            type: .update,
            subType: .generic,
            asMaster: true,
            data: structuralData
        )
        _ = try await playerController.handleMap(structuralResponse)

        let playerMap = playerRoot.mapRoot.gameController.gameItem(for: initial.itemId)
        #expect(playerMap.name == masterMap.name)
        #expect(playerMap[entryId].isShown)
        #expect(playerController.gameModel.gameUpdateType == .map)
        #expect(!playerController.gameModel.pendingMapRequests.contains(initial.itemId))
    }

    @Test("A delayed store cannot overwrite newer structural content")
    func staleStoreDoesNotRollbackMapContent() async throws {
        // Given
        try await setUp()
        let initial = try await initialMapMessage(counter: 10)
        _ = try #require(try await playerController.handleMap(initial.message))
        let masterMap = masterRoot.mapRoot.gameController.gameItem(for: initial.itemId)
        masterMap.pinScale += 0.75
        let expectedPinScale = masterMap.pinScale
        let update = masterRoot.gameModel.outgoingMessage(
            counter: 30,
            type: .update,
            subType: .generic,
            asMaster: true,
            data: await masterRoot.mapRoot.mapGameControllable.networkMapContentUpdate(
                for: initial.itemId
            )
        )
        _ = try await playerController.handleMap(update)

        var staleStore = initial.message
        staleStore.counter = 20
        staleStore.type = .store
        staleStore.subType = .store

        // When
        let acknowledgement = try #require(try await playerController.handleMap(staleStore))

        // Then
        #expect(acknowledgement.subType == .ok)
        #expect(
            playerRoot.mapRoot.gameController.gameItem(for: initial.itemId).pinScale == expectedPinScale
        )
    }

    @Test("An older Map content update cannot roll a newer update backward")
    func staleMapContentUpdateIsIgnored() async throws {
        // Given
        try await setUp()
        let initial = try await initialMapMessage(counter: 10)
        _ = try #require(try await playerController.handleMap(initial.message))
        let masterMap = masterRoot.mapRoot.gameController.gameItem(for: initial.itemId)

        masterMap.name = "Newest structural content"
        let newer = masterRoot.gameModel.outgoingMessage(
            counter: 40,
            type: .update,
            subType: .generic,
            asMaster: true,
            data: await masterRoot.mapRoot.mapGameControllable.networkMapContentUpdate(
                for: initial.itemId
            )
        )
        masterMap.name = "Delayed older structural content"
        let older = masterRoot.gameModel.outgoingMessage(
            counter: 39,
            type: .update,
            subType: .generic,
            asMaster: true,
            data: await masterRoot.mapRoot.mapGameControllable.networkMapContentUpdate(
                for: initial.itemId
            )
        )

        // When
        _ = try await playerController.handleMap(newer)
        _ = try await playerController.handleMap(older)

        // Then
        #expect(
            playerRoot.mapRoot.gameController.gameItem(for: initial.itemId).name
                == "Newest structural content"
        )
    }

    @Test("A queued older Map content update cannot replace a newer queued update")
    func staleQueuedMapContentUpdateIsIgnored() async throws {
        // Given a base package, followed by two structural snapshots created in
        // transport order but delivered before that base exists on the player.
        try await setUp()
        let itemId = try #require(masterRoot.mapRoot.itemController.itemDataModel.items.first)
        let masterMap = masterRoot.mapRoot.gameController.gameItem(for: itemId)
        masterMap.name = "Journal base content"
        let baseData = try await masterRoot.mapRoot.mapGameControllable.createMapGameData(for: itemId)

        masterMap.name = "Newest queued structural content"
        let newer = masterRoot.gameModel.outgoingMessage(
            counter: 40,
            type: .update,
            subType: .generic,
            asMaster: true,
            data: await masterRoot.mapRoot.mapGameControllable.networkMapContentUpdate(for: itemId)
        )
        masterMap.name = "Delayed older queued content"
        let older = masterRoot.gameModel.outgoingMessage(
            counter: 39,
            type: .update,
            subType: .generic,
            asMaster: true,
            data: await masterRoot.mapRoot.mapGameControllable.networkMapContentUpdate(for: itemId)
        )
        let delayedBase = masterRoot.gameModel.outgoingMessage(
            counter: 10,
            type: .reveal,
            subType: .show,
            asMaster: true,
            data: baseData
        )

        // When
        _ = try #require(try await playerController.handleMap(newer))
        _ = try await playerController.handleMap(older)
        _ = try await playerController.handleMap(delayedBase)

        // Then the queued counter-40 snapshot wins over both the base package
        // and the delayed counter-39 snapshot.
        #expect(
            playerRoot.mapRoot.gameController.gameItem(for: itemId).name
                == "Newest queued structural content"
        )
    }

    @Test("A permanently incomplete background is requested once and never ACKed")
    func incompleteBackgroundDoesNotPresentOrAcknowledge() async throws {
        // Given
        try await setUp()
        let initial = try await initialMapMessage()
        _ = try #require(try await playerController.handleMap(initial.message))
        let backgroundId = try #require(
            playerRoot.mapRoot.gameController.gameItem(for: initial.itemId).photoId
        )
        let background = playerRoot.photoRoot.gameController.gameItem(for: backgroundId)
        let originalFile = try #require(background.fileUrl)
        let contentHash = try #require(originalFile.contentHash)
        background.fileUrl = FileUrl(
            fileId: originalFile.fileId,
            url: URL(filePath: "/missing/map-background.png"),
            location: originalFile.location,
            module: originalFile.module,
            relativeUrl: nil,
            contentHash: contentHash
        )
        playerController.gameModel.gameUpdateType = .none
        let reference = NetworkCodableDataType(
            id: initial.itemId,
            type: .map,
            version: initial.message.data.version,
            assetVersion: initial.message.data.assetVersion,
            contentVersion: initial.message.data.contentVersion
        )
        #expect(
            await playerRoot.mapRoot.mapGameControllable.mapAssetVersion(for: initial.itemId)
                == reference.assetVersion
        )
        #expect(
            playerController.gameModel.hasMapContentVersion(
                itemId: initial.itemId,
                contentVersion: reference.contentVersion
            )
        )
        #expect(
            await !playerRoot.mapRoot.mapGameControllable.hasBackgroundImage(itemId: initial.itemId)
        )
        let firstReveal = masterRoot.gameModel.outgoingMessage(
            counter: 20,
            type: .reveal,
            subType: .show,
            asMaster: true,
            data: reference
        )
        var secondReveal = firstReveal
        secondReveal.counter = 21

        // When
        let firstRequest = try #require(try await playerController.handleMap(firstReveal))
        let secondResponse = try await playerController.handleMap(secondReveal)

        // Then
        #expect(firstRequest.subType == .show)
        #expect(firstRequest.data.data == nil)
        #expect(firstRequest.data.assetVersion == reference.assetVersion)
        #expect(firstRequest.data.contentVersion == reference.contentVersion)
        #expect(secondResponse == nil)
        #expect(playerController.gameModel.gameUpdateType == .none)
        #expect(!playerController.gameModel.requestedRepairIds.contains(backgroundId))
    }

    @Test("A newer same-Map asset intent rejects an older Journal payload")
    func sameMapAssetIntentRejectsDelayedOldFile() async throws {
        // Given
        try await setUp()
        let initial = try await initialMapMessage(counter: 40)
        await networkController.handleFileUpdate(initial.message)
        let playerMap = playerRoot.mapRoot.gameController.gameItem(for: initial.itemId)
        playerMap.name = "Retain newer intent state"

        let replacementAssetVersion = initial.message.data.effectiveAssetVersion ^ 1
        let replacementReference = masterRoot.gameModel.outgoingMessage(
            counter: 42,
            type: .reveal,
            subType: .show,
            asMaster: true,
            data: NetworkCodableDataType(
                id: initial.itemId,
                type: .map,
                version: initial.message.data.version,
                assetVersion: replacementAssetVersion,
                contentVersion: initial.message.data.contentVersion
            )
        )
        await networkController.handleUpdate(replacementReference, id: UUID())

        var delayedOldFile = initial.message
        delayedOldFile.counter = 41

        // When
        await networkController.handleFileUpdate(delayedOldFile)

        // Then
        #expect(playerMap.name == "Retain newer intent state")
        let request = try #require(playerNetworkSpy.requestData as? GameNetworkModel)
        #expect(request.data.assetVersion == replacementAssetVersion)
    }
}
#endif

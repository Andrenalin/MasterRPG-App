// @copyright André Trettin

#if canImport(Testing)
import AdventureRPG
import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import GameRPG
@testable import SpaceRPG

@Suite("Space availability and transform message sequencing", .serialized)
@MainActor
struct SpaceMessageFlowTests {
    @Test("Space asset repair returns canonical bytes without a group rebroadcast")
    func spaceAssetRepairIsRequesterOnly() async throws {
        let env = try await Self.preparedEnvironment()
        let spaceId = try #require(env.masterRoot.spaceRoot.itemController.itemDataModel.items.first)
        let reference = await env.masterRoot.spaceRoot.gameControllable.share(id: spaceId)
        let request = env.player1Root.gameModel.outgoingMessage(
            counter: 4,
            type: .reveal,
            subType: .show,
            asMaster: false,
            purpose: .assetRequest,
            data: reference
        )
        let broadcastCount = env.masterNetworkSpy.sendResponseHistory.count

        let repair = try #require(try await env.master.handleSpace(request))

        #expect(repair.id == spaceId)
        #expect(repair.effectiveAssetVersion == reference.effectiveAssetVersion)
        #expect(repair.data != nil)
        #expect(env.masterNetworkSpy.sendResponseHistory.count == broadcastCount)
    }

    @Test("Completing a requested Space repair presents the imported object")
    func spaceRepairCompletionPresentsImportedObject() async throws {
        // Given
        let env = try await Self.preparedEnvironment()
        let spaceId = try #require(env.masterRoot.spaceRoot.itemController.itemDataModel.items.first)
        let reference = await env.masterRoot.spaceRoot.gameControllable.share(id: spaceId)
        let fullData = try await env.masterRoot.spaceRoot.gameControllable.createGameData(for: spaceId)
        let reveal = env.masterRoot.gameModel.outgoingMessage(
            counter: 1,
            type: .reveal,
            subType: .show,
            asMaster: true,
            data: reference
        )

        // When - a reference reveal records presentation intent and requests
        // the missing package, followed by a targeted full store response.
        _ = try #require(try await env.player1.handleSpace(reveal))
        #expect(await env.player1Root.spaceRoot.gameControllable.currentId != spaceId)
        let repair = env.masterRoot.gameModel.outgoingMessage(
            counter: 2,
            type: .store,
            subType: .store,
            asMaster: true,
            targetId: env.player1Config.id,
            data: fullData
        )
        _ = try #require(try await env.player1.handleSpace(repair))

        // Then
        #expect(await env.player1Root.spaceRoot.gameControllable.currentId == spaceId)
        #expect(env.player1.gameModel.gameUpdateType == .space)
    }

    @Test("Master ignores stale, duplicate, negative, and malformed Space lists")
    func masterIgnoresInvalidSpaceListSequence() async throws {
        // Given
        let env = try await Self.preparedEnvironment()
        let spaceId = try #require(env.masterRoot.spaceRoot.itemController.itemDataModel.items.first)
        let version = await env.masterRoot.spaceRoot.gameController.networkVersion(for: spaceId)

        _ = try await env.master.handleSpace(
            Self.spaceReport(from: env.player1Root, versions: [spaceId: version], counter: 5)
        )
        let baseline = env.masterNetworkSpy.sendResponseHistory.count
        #expect(env.masterRoot.spaceRoot.spaceGameControllable.isSpaceAvailable(
            itemId: spaceId,
            for: env.player1Config.id,
            masterId: env.masterConfig.id
        ))

        // When
        _ = try await env.master.handleSpace(
            Self.spaceReport(from: env.player1Root, versions: [:], counter: 4)
        )
        _ = try await env.master.handleSpace(
            Self.spaceReport(from: env.player1Root, versions: [:], counter: 5)
        )
        _ = try await env.master.handleSpace(
            Self.spaceReport(from: env.player1Root, versions: [:], counter: -1)
        )
        _ = try await env.master.handleSpace(
            Self.malformedSpaceReport(from: env.player1Root, counter: 10)
        )

        // Then
        #expect(env.masterNetworkSpy.sendResponseHistory.count == baseline)
        #expect(env.masterRoot.spaceRoot.spaceGameControllable.isSpaceAvailable(
            itemId: spaceId,
            for: env.player1Config.id,
            masterId: env.masterConfig.id
        ))

        // A malformed packet must not reserve its counter.
        _ = try await env.master.handleSpace(
            Self.spaceReport(from: env.player1Root, versions: [:], counter: 6)
        )
        #expect(env.masterNetworkSpy.sendResponseHistory.count == baseline + 1)
        #expect(!env.masterRoot.spaceRoot.spaceGameControllable.isSpaceAvailable(
            itemId: spaceId,
            for: env.player1Config.id,
            masterId: env.masterConfig.id
        ))
    }

    @Test("Player ignores stale authoritative Space lists and malformed packets do not advance sequence")
    func playerIgnoresInvalidAuthoritativeSpaceListSequence() async throws {
        // Given
        let env = try await MultiConnectionTestEnvironment.create()
        let spaceId = UUID()
        let version = 27
        let players = [
            spaceId: [
                env.masterConfig.id: version,
                env.player1Config.id: version
            ]
        ]

        _ = try await env.player1.handleSpace(
            Self.authoritativeSpaceList(
                from: env.masterRoot,
                counter: 5,
                list: [spaceId: version],
                players: players
            )
        )

        // When
        _ = try await env.player1.handleSpace(
            Self.authoritativeSpaceList(from: env.masterRoot, counter: 4, list: [:], players: [:])
        )
        _ = try await env.player1.handleSpace(
            Self.authoritativeSpaceList(from: env.masterRoot, counter: 5, list: [:], players: [:])
        )
        _ = try await env.player1.handleSpace(
            Self.authoritativeSpaceList(from: env.masterRoot, counter: -1, list: [:], players: [:])
        )
        _ = try await env.player1.handleSpace(
            Self.malformedAuthoritativeSpaceList(from: env.masterRoot, counter: 10)
        )

        // Then
        #expect(env.player1Root.spaceRoot.spaceGameControllable.masterVersion(
            for: spaceId,
            masterId: env.masterConfig.id
        ) == version)
        #expect(env.player1Root.spaceRoot.spaceGameControllable.isSpaceAvailable(
            itemId: spaceId,
            for: env.player1Config.id,
            masterId: env.masterConfig.id
        ))

        // Counter 10 was malformed, so a later valid counter 6 still applies.
        _ = try await env.player1.handleSpace(
            Self.authoritativeSpaceList(from: env.masterRoot, counter: 6, list: [:], players: [:])
        )
        #expect(env.player1Root.spaceRoot.spaceGameControllable.masterVersion(
            for: spaceId,
            masterId: env.masterConfig.id
        ) == nil)
    }

    @Test("Lost player is removed from Space reports and may report again from a reset counter")
    func lostPlayerClearsSpaceAvailabilityAndSequence() async throws {
        // Given
        let env = try await Self.preparedEnvironment()
        let spaceId = try #require(env.masterRoot.spaceRoot.itemController.itemDataModel.items.first)
        let version = await env.masterRoot.spaceRoot.gameController.networkVersion(for: spaceId)
        let connectionId = ConnectionController.ID()
        let report = Self.spaceReport(
            from: env.player1Root,
            versions: [spaceId: version],
            counter: 8
        )

        await env.master.receivedProcess(report, connectionId: connectionId)
        #expect(env.masterRoot.spaceRoot.spaceGameControllable.isSpaceAvailable(
            itemId: spaceId,
            for: env.player1Config.id,
            masterId: env.masterConfig.id
        ))

        // When
        await env.master.lostPlayer(for: connectionId)

        // Then
        #expect(!env.masterRoot.spaceRoot.spaceGameControllable.isSpaceAvailable(
            itemId: spaceId,
            for: env.player1Config.id,
            masterId: env.masterConfig.id
        ))
        #expect(env.masterRoot.spaceRoot.spaceGameControllable.reportedVersion(
            for: spaceId,
            playerId: env.player1Config.id
        ) == nil)
        #expect(!env.masterRoot.spaceRoot.gameController.gameModel.playerReport(for: spaceId).contains(env.player1Config.id))

        let baseline = env.masterNetworkSpy.sendResponseHistory.count
        _ = try await env.master.handleSpace(
            Self.spaceReport(from: env.player1Root, versions: [spaceId: version], counter: 1)
        )

        #expect(env.masterNetworkSpy.sendResponseHistory.count == baseline + 1)
        #expect(env.masterRoot.spaceRoot.spaceGameControllable.isSpaceAvailable(
            itemId: spaceId,
            for: env.player1Config.id,
            masterId: env.masterConfig.id
        ))
    }

    @Test("Space list updates are not presentation intents")
    func spaceListIsNotPresentationIntent() async throws {
        // Given
        let env = try await MultiConnectionTestEnvironment.create()
        let model = Self.authoritativeSpaceList(
            from: env.masterRoot,
            counter: 5,
            list: [UUID(): 7],
            players: [:]
        )

        // Then
        #expect(model.sender.isMaster)
        #expect(model.type == .update)
        #expect(model.subType == .spaceList)
        #expect(!model.isPresentationIntent)
    }

    @Test("Player optimistically acknowledges its exact outgoing Space transform envelope")
    func playerAppliesOutgoingSpaceTransformLocally() async throws {
        // Given
        let env = try await MultiConnectionTestEnvironment.create()
        let spaceId = UUID()
        let version = 37
        let transform = SpaceTransformModel(
            position: SIMD3<Float>(3, 4, 5),
            scale: SIMD3<Float>(repeating: 2),
            yaw: 0.4,
            pitch: 0.2
        )
        let data = NetworkCodableDataType(
            id: spaceId,
            type: .space,
            version: version,
            data: transform.encodeData()
        )
        let retainedTimestamp = Date.now.timeIntervalSince1970 + 60
        let retainedTransform = SpaceTransformModel(
            position: SIMD3<Float>(repeating: 0),
            scale: SIMD3<Float>(repeating: 1),
            yaw: 0,
            pitch: 0
        )
        #expect(env.player1Root.spaceRoot.gameController.spaceGameModel.applyTransform(
            itemId: spaceId,
            version: version,
            counter: 50_000,
            timestamp: retainedTimestamp,
            transform: retainedTransform
        ))

        // When
        await env.player1.game(message: data, actionType: .spaceTransform)

        // Then
        let outgoing = try #require(env.playerNetworkSpy.requestData as? GameNetworkModel)
        let retained = try #require(
            env.player1Root.spaceRoot.gameController.spaceGameModel.transformStates[spaceId]?[version]
        )
        #expect(outgoing.type == .update)
        #expect(outgoing.subType == .spaceTransform)
        #expect(outgoing.effectiveAudience == .group)
        #expect(outgoing.data == data)
        #expect(outgoing.timestamp > retainedTimestamp)
        #expect(retained.transform == transform)
        #expect(retained.counter == outgoing.counter)
        #expect(retained.timestamp == outgoing.timestamp)
    }

    @Test("Master repairs its Space when player sharing is disabled")
    func masterRepairsCanonicalSpaceWhenSharingIsDisabled() async throws {
        // Given
        let env = try await Self.preparedEnvironment()
        env.masterRoot.gameModel.gameControl.features.spaceSharing = false
        let spaceId = try #require(env.masterRoot.spaceRoot.itemController.itemDataModel.items.first)
        let canonicalBefore = try await env.masterRoot.spaceRoot.gameController.createGameData(for: spaceId)
        let version = canonicalBefore.effectiveAssetVersion
        #expect(canonicalBefore.data?.isEmpty == false)
        let request = env.player1Root.gameModel.outgoingMessage(
            counter: 4,
            type: .reveal,
            subType: .show,
            asMaster: false,
            data: NetworkCodableDataType(id: spaceId, type: .space, version: version)
        )
        let broadcastCount = env.masterNetworkSpy.sendResponseHistory.count

        // When
        let repair = try await env.master.handleSpace(request)

        // Then - the common request path will target this package only at the
        // requester; handling it directly must not publish a group reveal.
        let canonical = try #require(repair)
        #expect(canonical.id == spaceId)
        #expect(canonical.type == .space)
        #expect(canonical.effectiveAssetVersion == version)
        #expect(canonical.data?.isEmpty == false)
        #expect(env.masterNetworkSpy.sendResponseHistory.count == broadcastCount)

        // A player payload is still a forbidden player-initiated presentation.
        let peerBytes = Data("peer Space bytes".utf8)
        let peerReveal = env.player1Root.gameModel.outgoingMessage(
            counter: 5,
            type: .reveal,
            subType: .show,
            asMaster: false,
            data: NetworkCodableDataType(
                id: spaceId,
                type: .space,
                version: version,
                data: peerBytes
            )
        )
        #expect(try await env.master.handleSpace(peerReveal) == nil)
        let canonicalAfter = try await env.masterRoot.spaceRoot.gameController.createGameData(for: spaceId)
        #expect(env.masterNetworkSpy.sendResponseHistory.count == broadcastCount)
        #expect(canonicalAfter.effectiveAssetVersion == version)
        #expect(canonicalAfter.data?.isEmpty == false)
        #expect(canonicalAfter.data != peerBytes)
    }

    @Test("Master applies a player Space group transform locally without a canonical rebroadcast")
    func masterAppliesPlayerGroupTransformWithoutRebroadcast() async throws {
        // Given
        let env = try await Self.preparedEnvironment()
        let spaceId = try #require(env.masterRoot.spaceRoot.itemController.itemDataModel.items.first)
        let version = await env.masterRoot.spaceRoot.gameController.networkVersion(for: spaceId)
        _ = try await env.master.handleSpace(
            Self.spaceReport(from: env.player1Root, versions: [spaceId: version], counter: 2)
        )
        let transform = SpaceTransformModel(
            position: SIMD3<Float>(1, 2, 3),
            scale: SIMD3<Float>(2, 2, 2),
            yaw: 0.5,
            pitch: 0.25
        )
        let firstTimestamp: TimeInterval = 10_000
        let playerEvent = Self.playerTransform(
            from: env.player1Root,
            itemId: spaceId,
            version: version,
            counter: 7,
            timestamp: firstTimestamp,
            transform: transform
        )
        let baseline = env.masterNetworkSpy.sendResponseHistory.count

        // When
        _ = try await env.master.handleSpace(playerEvent)

        // Then - The original group event is already routed by the transport;
        // the master only validates and applies its local copy.
        let retained = env.masterRoot.spaceRoot.spaceGameControllable.latestSpaceTransform(
            for: spaceId,
            version: version
        )
        #expect(playerEvent.effectiveAudience == .group)
        #expect(playerEvent.sender.role == .player)
        #expect(SpaceTransformModel.decodeData(of: retained?.data) == transform)
        #expect(env.masterNetworkSpy.sendResponseHistory.count == baseline)

        // When - A newer counter with an older timestamp and a competing asset
        // version arrive. Neither may replace the retained transform.
        let ignoredTransform = SpaceTransformModel(
            position: SIMD3<Float>(9, 9, 9),
            scale: SIMD3<Float>(1, 1, 1),
            yaw: 1,
            pitch: 1
        )
        _ = try await env.master.handleSpace(
            Self.playerTransform(
                from: env.player1Root,
                itemId: spaceId,
                version: version,
                counter: 8,
                timestamp: firstTimestamp - 1,
                transform: ignoredTransform
            )
        )
        _ = try await env.master.handleSpace(
            Self.playerTransform(
                from: env.player1Root,
                itemId: spaceId,
                version: version + 1,
                counter: 9,
                timestamp: firstTimestamp + 1,
                transform: ignoredTransform
            )
        )

        // Then
        let retainedAfterIgnored = env.masterRoot.spaceRoot.spaceGameControllable.latestSpaceTransform(
            for: spaceId,
            version: version
        )
        #expect(SpaceTransformModel.decodeData(of: retainedAfterIgnored?.data) == transform)
        #expect(env.masterNetworkSpy.sendResponseHistory.count == baseline)

        // When - The stale timestamp did not reserve counter 8, so that same
        // counter can carry a genuinely newer intent.
        _ = try await env.master.handleSpace(
            Self.playerTransform(
                from: env.player1Root,
                itemId: spaceId,
                version: version,
                counter: 8,
                timestamp: firstTimestamp + 2,
                transform: ignoredTransform
            )
        )

        // Then
        let retainedAfterNewer = env.masterRoot.spaceRoot.spaceGameControllable.latestSpaceTransform(
            for: spaceId,
            version: version
        )
        #expect(SpaceTransformModel.decodeData(of: retainedAfterNewer?.data) == ignoredTransform)
        #expect(env.masterNetworkSpy.sendResponseHistory.count == baseline)
    }

    @Test("Player applies the newest matching Space group transform from an available peer")
    func playerAppliesNewestAvailablePeerGroupTransform() async throws {
        // Given
        let env = try await MultiConnectionTestEnvironment.create()
        let spaceId = UUID()
        let version = 41
        let masterTransform = SpaceTransformModel(
            position: SIMD3<Float>(1, 2, 3),
            scale: SIMD3<Float>(repeating: 1),
            yaw: 0.25,
            pitch: 0.5
        )
        let peerTransform = SpaceTransformModel(
            position: SIMD3<Float>(9, 9, 9),
            scale: SIMD3<Float>(repeating: 2),
            yaw: 1,
            pitch: 1
        )
        let ignoredTransform = SpaceTransformModel(
            position: SIMD3<Float>(4, 5, 6),
            scale: SIMD3<Float>(repeating: 3),
            yaw: 0.75,
            pitch: 0.5
        )
        let masterTimestamp: TimeInterval = 20_000
        _ = try await env.player1.handleSpace(
            Self.authoritativeSpaceList(
                from: env.masterRoot,
                counter: 2,
                list: [spaceId: version],
                players: [
                    spaceId: [
                        env.masterConfig.id: version,
                        env.player1Config.id: version,
                        env.player2Config.id: version
                    ]
                ]
            )
        )
        let masterEvent = Self.transformMessage(
            from: env.masterRoot,
            asMaster: true,
            itemId: spaceId,
            version: version,
            counter: 100,
            timestamp: masterTimestamp,
            transform: masterTransform
        )
        var peerEvent = Self.transformMessage(
            from: env.player2Root,
            asMaster: false,
            itemId: spaceId,
            version: version,
            counter: 1,
            timestamp: masterTimestamp + 1,
            transform: peerTransform
        )
        peerEvent.masterId = env.masterConfig.id

        // When
        _ = try await env.player1.handleSpace(masterEvent)
        _ = try await env.player1.handleSpace(peerEvent)

        // Then - The peer's lower counter still wins because its intent
        // timestamp is newer, and the protocol classifies it as a group event.
        let retainedAfterPeer = env.player1Root.spaceRoot.spaceGameControllable.latestSpaceTransform(
            for: spaceId,
            version: version
        )
        #expect(peerEvent.effectiveAudience == .group)
        #expect(peerEvent.sender.role == .player)
        #expect(SpaceTransformModel.decodeData(of: retainedAfterPeer?.data) == peerTransform)

        // When - A higher-counter master packet is older, the wrong asset
        // version is not current, and a peer without an availability report is
        // not eligible to move this Space.
        _ = try await env.player1.handleSpace(
            Self.transformMessage(
                from: env.masterRoot,
                asMaster: true,
                itemId: spaceId,
                version: version + 1,
                counter: 1_000,
                timestamp: masterTimestamp + 10,
                transform: ignoredTransform
            )
        )
        _ = try await env.player1.handleSpace(
            Self.transformMessage(
                from: env.masterRoot,
                asMaster: true,
                itemId: spaceId,
                version: version,
                counter: 1_000,
                timestamp: masterTimestamp - 1,
                transform: ignoredTransform
            )
        )
        var unavailablePeerEvent = Self.transformMessage(
            from: env.player3Root,
            asMaster: false,
            itemId: spaceId,
            version: version,
            counter: 2_000,
            timestamp: masterTimestamp + 20,
            transform: ignoredTransform
        )
        unavailablePeerEvent.masterId = env.masterConfig.id
        _ = try await env.player1.handleSpace(unavailablePeerEvent)

        // Then
        let retained = env.player1Root.spaceRoot.spaceGameControllable.latestSpaceTransform(
            for: spaceId,
            version: version
        )
        #expect(SpaceTransformModel.decodeData(of: retained?.data) == peerTransform)
        #expect(env.player1Root.spaceRoot.spaceGameControllable.latestSpaceTransform(
            for: spaceId,
            version: version + 1
        ) == nil)
    }

    @Test("A peer Space transform waits for the authoritative list and retains the newest intent")
    func playerRetriesPeerTransformAfterAuthoritativeList() async throws {
        // Given: a peer's small group events overtake the master's authoritative
        // availability list on another player.
        let env = try await MultiConnectionTestEnvironment.create()
        let spaceId = UUID()
        let version = 57
        let olderTransform = SpaceTransformModel(
            position: SIMD3<Float>(1, 2, 3),
            scale: SIMD3<Float>(repeating: 1),
            yaw: 0.25,
            pitch: 0.5
        )
        let newestTransform = SpaceTransformModel(
            position: SIMD3<Float>(7, 8, 9),
            scale: SIMD3<Float>(repeating: 2),
            yaw: 1,
            pitch: 0.75
        )
        let baseTimestamp = Date.now.timeIntervalSince1970 - 10
        var newestEvent = Self.transformMessage(
            from: env.player2Root,
            asMaster: false,
            itemId: spaceId,
            version: version,
            counter: 10,
            timestamp: baseTimestamp + 1,
            transform: newestTransform
        )
        newestEvent.masterId = env.masterConfig.id
        var delayedOlderEvent = Self.transformMessage(
            from: env.player2Root,
            asMaster: false,
            itemId: spaceId,
            version: version,
            counter: 11,
            timestamp: baseTimestamp,
            transform: olderTransform
        )
        delayedOlderEvent.masterId = env.masterConfig.id

        // When: newest then older arrive before the availability prerequisite.
        #expect(try await env.player1.handleSpace(newestEvent) == nil)
        #expect(try await env.player1.handleSpace(delayedOlderEvent) == nil)
        #expect(env.player1Root.spaceRoot.spaceGameControllable.latestSpaceTransform(
            for: spaceId,
            version: version
        ) == nil)

        // And the master list confirms that the peer has this exact asset.
        _ = try await env.player1.handleSpace(
            Self.authoritativeSpaceList(
                from: env.masterRoot,
                counter: 2,
                list: [spaceId: version],
                players: [
                    spaceId: [
                        env.masterConfig.id: version,
                        env.player1Config.id: version,
                        env.player2Config.id: version
                    ]
                ]
            )
        )

        // Then: deferred replay keeps timestamp ordering despite delivery order.
        let retained = env.player1Root.spaceRoot.spaceGameControllable.latestSpaceTransform(
            for: spaceId,
            version: version
        )
        #expect(SpaceTransformModel.decodeData(of: retained?.data) == newestTransform)
    }
}

private extension SpaceMessageFlowTests {
    static func preparedEnvironment() async throws -> MultiConnectionTestEnvironment {
        let env = try await MultiConnectionTestEnvironment.create()
        try await MockRoot.importTestData(
            into: env.masterRoot.adventureRoot,
            name: ResourcesDebug.spaceTestData,
            itemCounter: 0
        )
        env.masterRoot.adventureRoot.startGame()
        return env
    }

    static func spaceReport(
        from root: GameRoot,
        versions: [UUID: Int],
        counter: Int
    ) -> GameNetworkModel {
        root.gameModel.outgoingMessage(
            counter: counter,
            type: .update,
            subType: .spaceList,
            asMaster: false,
            data: NetworkCodableDataType(
                id: UUID(),
                type: .space,
                version: 0,
                data: SpaceListRequest(list: versions, players: [:]).encodeData()
            )
        )
    }

    static func malformedSpaceReport(from root: GameRoot, counter: Int) -> GameNetworkModel {
        root.gameModel.outgoingMessage(
            counter: counter,
            type: .update,
            subType: .spaceList,
            asMaster: false,
            data: NetworkCodableDataType(
                id: UUID(),
                type: .space,
                version: 0,
                data: Data([0xFF])
            )
        )
    }

    static func authoritativeSpaceList(
        from root: GameRoot,
        counter: Int,
        list: [UUID: Int],
        players: [UUID: [UUID: Int]]
    ) -> GameNetworkModel {
        root.gameModel.outgoingMessage(
            counter: counter,
            type: .update,
            subType: .spaceList,
            asMaster: true,
            data: NetworkCodableDataType(
                id: UUID(),
                type: .space,
                version: 0,
                data: SpaceListRequest(list: list, players: players).encodeData()
            )
        )
    }

    static func malformedAuthoritativeSpaceList(from root: GameRoot, counter: Int) -> GameNetworkModel {
        root.gameModel.outgoingMessage(
            counter: counter,
            type: .update,
            subType: .spaceList,
            asMaster: true,
            data: NetworkCodableDataType(
                id: UUID(),
                type: .space,
                version: 0,
                data: Data([0xFF])
            )
        )
    }

    static func playerTransform(
        from root: GameRoot,
        itemId: UUID,
        version: Int,
        counter: Int,
        timestamp: TimeInterval = Date.now.timeIntervalSince1970,
        transform: SpaceTransformModel
    ) -> GameNetworkModel {
        root.gameModel.outgoingMessage(
            timestamp: timestamp,
            counter: counter,
            type: .update,
            subType: .spaceTransform,
            asMaster: false,
            data: NetworkCodableDataType(
                id: itemId,
                type: .space,
                version: version,
                data: transform.encodeData()
            )
        )
    }

    static func transformMessage(
        from root: GameRoot,
        asMaster: Bool,
        itemId: UUID,
        version: Int,
        counter: Int,
        timestamp: TimeInterval = Date.now.timeIntervalSince1970,
        transform: SpaceTransformModel
    ) -> GameNetworkModel {
        root.gameModel.outgoingMessage(
            timestamp: timestamp,
            counter: counter,
            type: .update,
            subType: .spaceTransform,
            asMaster: asMaster,
            data: NetworkCodableDataType(
                id: itemId,
                type: .space,
                version: version,
                data: transform.encodeData()
            )
        )
    }
}
#endif

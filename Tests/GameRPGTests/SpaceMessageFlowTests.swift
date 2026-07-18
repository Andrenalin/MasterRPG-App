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

    @Test("Master repairs its Space when player sharing is disabled")
    func masterRepairsCanonicalSpaceWhenSharingIsDisabled() async throws {
        // Given
        let env = try await Self.preparedEnvironment()
        env.masterRoot.gameModel.gameControl.features.spaceSharing = false
        let spaceId = try #require(env.masterRoot.spaceRoot.itemController.itemDataModel.items.first)
        let canonicalBefore = try await env.masterRoot.spaceRoot.gameController.createGameData(for: spaceId)
        let version = canonicalBefore.effectiveAssetVersion
        let canonicalBytes = try #require(canonicalBefore.data)
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
        #expect(canonical.data == canonicalBytes)
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
        #expect(canonicalAfter.data == canonicalBytes)
        #expect(canonicalAfter.data != peerBytes)
    }

    @Test("Master validates and sequences player transforms before authoritative rebroadcast")
    func masterAuthoritativeTransformRejectsStaleAndWrongVersion() async throws {
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
        let baseline = env.masterNetworkSpy.sendResponseHistory.count

        // When
        _ = try await env.master.handleSpace(
            Self.playerTransform(
                from: env.player1Root,
                itemId: spaceId,
                version: version,
                counter: 7,
                transform: transform
            )
        )

        // Then - The master publishes one canonical transform under its identity.
        let sent = env.masterNetworkSpy.sendResponseHistory
            .dropFirst(baseline)
            .compactMap { $0 as? GameNetworkModel }
        let authoritative = try #require(sent.first)
        #expect(sent.count == 1)
        #expect(authoritative.sender.isMaster)
        #expect(authoritative.type == .update)
        #expect(authoritative.subType == .spaceTransform)
        #expect(authoritative.data.id == spaceId)
        #expect(authoritative.data.effectiveAssetVersion == version)
        #expect(SpaceTransformModel.decodeData(of: authoritative.data.data) == transform)

        // When - Older/duplicate counters and a competing asset version arrive.
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
                counter: 6,
                transform: ignoredTransform
            )
        )
        _ = try await env.master.handleSpace(
            Self.playerTransform(
                from: env.player1Root,
                itemId: spaceId,
                version: version,
                counter: 7,
                transform: ignoredTransform
            )
        )
        _ = try await env.master.handleSpace(
            Self.playerTransform(
                from: env.player1Root,
                itemId: spaceId,
                version: version + 1,
                counter: 8,
                transform: ignoredTransform
            )
        )

        // Then
        #expect(env.masterNetworkSpy.sendResponseHistory.count == baseline + 1)
    }

    @Test("Player accepts only master transforms for the matching Space version")
    func playerAcceptsOnlyMatchingMasterTransforms() async throws {
        // Given
        let env = try await MultiConnectionTestEnvironment.create()
        let spaceId = UUID()
        let otherSpaceId = UUID()
        let version = 41
        let first = SpaceTransformModel(
            position: SIMD3<Float>(1, 2, 3),
            scale: SIMD3<Float>(repeating: 1),
            yaw: 0.25,
            pitch: 0.5
        )
        let ignored = SpaceTransformModel(
            position: SIMD3<Float>(9, 9, 9),
            scale: SIMD3<Float>(repeating: 2),
            yaw: 1,
            pitch: 1
        )
        _ = try await env.player1.handleSpace(
            Self.authoritativeSpaceList(
                from: env.masterRoot,
                counter: 2,
                list: [spaceId: version],
                players: [:]
            )
        )

        // When
        _ = try await env.player1.handleSpace(
            Self.transformMessage(
                from: env.masterRoot,
                asMaster: true,
                itemId: spaceId,
                version: version,
                counter: 5,
                transform: first
            )
        )
        _ = try await env.player1.handleSpace(
            Self.transformMessage(
                from: env.player2Root,
                asMaster: false,
                itemId: spaceId,
                version: version,
                counter: 6,
                transform: ignored
            )
        )
        _ = try await env.player1.handleSpace(
            Self.transformMessage(
                from: env.masterRoot,
                asMaster: true,
                itemId: spaceId,
                version: version + 1,
                counter: 10,
                transform: ignored
            )
        )
        _ = try await env.player1.handleSpace(
            Self.transformMessage(
                from: env.masterRoot,
                asMaster: true,
                itemId: spaceId,
                version: version,
                counter: 4,
                transform: ignored
            )
        )
        _ = try await env.player1.handleSpace(
            Self.transformMessage(
                from: env.masterRoot,
                asMaster: true,
                itemId: otherSpaceId,
                version: 7,
                counter: 3,
                transform: ignored
            )
        )

        // Then
        let retained = env.player1Root.spaceRoot.spaceGameControllable.latestSpaceTransform(
            for: spaceId,
            version: version
        )
        let otherRetained = env.player1Root.spaceRoot.spaceGameControllable.latestSpaceTransform(
            for: otherSpaceId,
            version: 7
        )
        #expect(SpaceTransformModel.decodeData(of: retained?.data) == first)
        #expect(SpaceTransformModel.decodeData(of: otherRetained?.data) == ignored)
        #expect(env.player1Root.spaceRoot.spaceGameControllable.latestSpaceTransform(
            for: spaceId,
            version: version + 1
        ) == nil)
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
        transform: SpaceTransformModel
    ) -> GameNetworkModel {
        root.gameModel.outgoingMessage(
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
        transform: SpaceTransformModel
    ) -> GameNetworkModel {
        root.gameModel.outgoingMessage(
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

// @copyright André Trettin

import CoreRPG
import Foundation
import Testing
import simd

@testable import SpaceRPG

@MainActor
struct GameControllerTests {
    @Test("Space lists aggregate matching participant versions and remove a lost player")
    func spaceListAggregatesVersionsAndRemovesPlayer() async throws {
        // Given
        let root = SpaceRootModel.testRoot()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let masterId = UUID()
        let matchingPlayerId = UUID()
        let partiallyMatchingPlayerId = UUID()
        let firstSpaceId = UUID()
        let secondSpaceId = UUID()

        root.itemController.replace(
            model: SpaceModel(id: firstSpaceId, name: "Tower", displayState: 0),
            isInsert: true
        )
        root.itemController.replace(
            model: SpaceModel(id: secondSpaceId, name: "Dragon", displayState: 0),
            isInsert: true
        )

        let localData = await sut.spaceList(allPlayers: false, with: masterId)
        let localList = try #require(SpaceListRequest.decodeData(of: localData.data))
        let firstVersion = try #require(localList.list[firstSpaceId])
        let secondVersion = try #require(localList.list[secondSpaceId])
        #expect(localList.players.isEmpty)

        let matchingList = SpaceListRequest(
            list: [firstSpaceId: firstVersion, secondSpaceId: secondVersion],
            players: [:]
        )
        let partiallyMatchingList = SpaceListRequest(
            list: [
                firstSpaceId: firstVersion &+ 1,
                secondSpaceId: secondVersion
            ],
            players: [:]
        )

        // When
        let appliedMatching = await sut.applySpaceList(
            data: Self.spaceListData(matchingList),
            for: matchingPlayerId,
            with: masterId,
            authoritative: false
        )
        let appliedPartial = await sut.applySpaceList(
            data: Self.spaceListData(partiallyMatchingList),
            for: partiallyMatchingPlayerId,
            with: masterId,
            authoritative: false
        )
        let authoritativeData = await sut.spaceList(allPlayers: true, with: masterId)
        let authoritativeList = try #require(SpaceListRequest.decodeData(of: authoritativeData.data))

        // Then
        #expect(appliedMatching)
        #expect(appliedPartial)
        #expect(authoritativeList.list == localList.list)
        #expect(authoritativeList.players[firstSpaceId]?[masterId] == firstVersion)
        #expect(authoritativeList.players[firstSpaceId]?[matchingPlayerId] == firstVersion)
        #expect(authoritativeList.players[firstSpaceId]?[partiallyMatchingPlayerId] == firstVersion &+ 1)
        #expect(Set(sut.gameModel.playerReport(for: firstSpaceId)) == [masterId, matchingPlayerId])
        #expect(
            Set(sut.gameModel.playerReport(for: secondSpaceId)) ==
                [masterId, matchingPlayerId, partiallyMatchingPlayerId]
        )

        // When
        sut.removeSpaceReports(for: matchingPlayerId)

        // Then
        #expect(sut.reportedVersion(for: firstSpaceId, playerId: matchingPlayerId) == nil)
        #expect(sut.reportedVersion(for: secondSpaceId, playerId: matchingPlayerId) == nil)
        #expect(!sut.gameModel.playerReport(for: firstSpaceId).contains(matchingPlayerId))
        #expect(!sut.gameModel.playerReport(for: secondSpaceId).contains(matchingPlayerId))
        #expect(sut.isSpaceAvailable(
            itemId: secondSpaceId,
            for: partiallyMatchingPlayerId,
            masterId: masterId
        ))
    }

    @Test("Space transforms remain isolated by item and asset version")
    func transformsRemainIsolatedByItemAndVersion() async throws {
        // Given
        let root = SpaceRootModel.testRoot()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let firstSpaceId = UUID()
        let secondSpaceId = UUID()
        let firstTransform = Self.transform(seed: 1)
        let secondTransform = Self.transform(seed: 2)
        let newerFirstTransform = Self.transform(seed: 3)

        // When
        let appliedFirst = sut.applySpaceTransform(
            data: Self.transformData(
                itemId: firstSpaceId,
                version: 11,
                transform: firstTransform
            ),
            counter: 4,
            timestamp: 0
        )
        let appliedSecond = sut.applySpaceTransform(
            data: Self.transformData(
                itemId: secondSpaceId,
                version: 22,
                transform: secondTransform
            ),
            counter: 5,
            timestamp: 0
        )
        let appliedNewerFirst = sut.applySpaceTransform(
            data: Self.transformData(
                itemId: firstSpaceId,
                version: 22,
                transform: newerFirstTransform
            ),
            counter: 6,
            timestamp: 0
        )

        // Then
        #expect(appliedFirst)
        #expect(appliedSecond)
        #expect(appliedNewerFirst)
        #expect(Self.decodedTransform(sut.latestSpaceTransform(for: firstSpaceId, version: 11)) == firstTransform)
        #expect(Self.decodedTransform(sut.latestSpaceTransform(for: firstSpaceId, version: 22)) == newerFirstTransform)
        #expect(Self.decodedTransform(sut.latestSpaceTransform(for: secondSpaceId, version: 22)) == secondTransform)
        #expect(sut.latestSpaceTransform(for: secondSpaceId, version: 11) == nil)
    }

    @Test("Stale and malformed Space transforms are ignored without advancing state")
    func staleAndMalformedTransformsAreIgnored() async throws {
        // Given
        let root = SpaceRootModel.testRoot()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let itemId = UUID()
        let currentTransform = Self.transform(seed: 3)
        let nextTransform = Self.transform(seed: 4)
        let currentData = Self.transformData(itemId: itemId, version: 31, transform: currentTransform)

        #expect(sut.applySpaceTransform(data: currentData, counter: 8, timestamp: 0))

        // When
        let duplicateApplied = sut.applySpaceTransform(
            data: Self.transformData(itemId: itemId, version: 31, transform: nextTransform),
            counter: 8,
            timestamp: 0
        )
        let staleApplied = sut.applySpaceTransform(
            data: Self.transformData(itemId: itemId, version: 31, transform: nextTransform),
            counter: 7,
            timestamp: 0
        )
        let legacyAppliedAfterSequencedState = sut.applySpaceTransform(
            data: Self.transformData(itemId: itemId, version: 31, transform: nextTransform),
            counter: 0,
            timestamp: 0
        )
        let negativeApplied = sut.applySpaceTransform(
            data: Self.transformData(itemId: itemId, version: 31, transform: nextTransform),
            counter: -1,
            timestamp: 0
        )
        let malformedApplied = sut.applySpaceTransform(
            data: NetworkCodableDataType(
                id: itemId,
                type: .space,
                version: 31,
                data: Data("not a transform".utf8)
            ),
            counter: 50,
            timestamp: 0
        )
        let wrongModuleApplied = sut.applySpaceTransform(
            data: NetworkCodableDataType(
                id: itemId,
                type: .photo,
                version: 31,
                data: nextTransform.encodeData()
            ),
            counter: 50,
            timestamp: 0
        )

        // Then
        #expect(!duplicateApplied)
        #expect(!staleApplied)
        #expect(!legacyAppliedAfterSequencedState)
        #expect(!negativeApplied)
        #expect(!malformedApplied)
        #expect(!wrongModuleApplied)
        #expect(Self.decodedTransform(sut.latestSpaceTransform(for: itemId, version: 31)) == currentTransform)

        // When - malformed counter 50 did not reserve the sequence.
        let nextApplied = sut.applySpaceTransform(
            data: Self.transformData(itemId: itemId, version: 31, transform: nextTransform),
            counter: 9,
            timestamp: 0
        )

        // Then
        #expect(nextApplied)
        #expect(Self.decodedTransform(sut.latestSpaceTransform(for: itemId, version: 31)) == nextTransform)
    }

    @Test("Newest Space transform timestamp wins and a future timestamp does not replace state")
    func newestTransformTimestampWins() async throws {
        // Given
        let root = SpaceRootModel.testRoot()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let itemId = UUID()
        let firstTransform = Self.transform(seed: 7)
        let newerTransform = Self.transform(seed: 8)
        let staleTransform = Self.transform(seed: 9)
        let finalTransform = Self.transform(seed: 10)
        let firstTimestamp: TimeInterval = 1_000
        let newerTimestamp: TimeInterval = 2_000

        // When
        let firstApplied = sut.applySpaceTransform(
            data: Self.transformData(itemId: itemId, version: 51, transform: firstTransform),
            counter: 100,
            timestamp: firstTimestamp
        )
        let newerApplied = sut.applySpaceTransform(
            data: Self.transformData(itemId: itemId, version: 51, transform: newerTransform),
            counter: 1,
            timestamp: newerTimestamp
        )
        let staleApplied = sut.applySpaceTransform(
            data: Self.transformData(itemId: itemId, version: 51, transform: staleTransform),
            counter: 1_000,
            timestamp: firstTimestamp + 1
        )
        let equalTimestampApplied = sut.applySpaceTransform(
            data: Self.transformData(itemId: itemId, version: 51, transform: staleTransform),
            counter: 10_000,
            timestamp: newerTimestamp
        )
        let futureApplied = sut.applySpaceTransform(
            data: Self.transformData(itemId: itemId, version: 51, transform: staleTransform),
            counter: 2_000,
            timestamp: Date.now.timeIntervalSince1970 + 3_600
        )
        let finalApplied = sut.applySpaceTransform(
            data: Self.transformData(itemId: itemId, version: 51, transform: finalTransform),
            counter: 2_000,
            timestamp: newerTimestamp + 1
        )

        // Then
        #expect(firstApplied)
        #expect(newerApplied)
        #expect(!staleApplied)
        #expect(!equalTimestampApplied)
        #expect(!futureApplied)
        #expect(finalApplied)
        #expect(Self.decodedTransform(sut.latestSpaceTransform(for: itemId, version: 51)) == finalTransform)
    }

    @Test("Local Space transform timestamp advances after retained state within the future bound")
    func localTransformTimestampIsCausallyBounded() throws {
        // Given
        let sut = SpaceGameModel()
        let itemId = UUID()
        let saturatedItemId = UUID()
        let version = 61
        let now: TimeInterval = 10_000
        let retainedTimestamp = now + 100
        let transform = Self.transform(seed: 11)

        #expect(sut.causalTransformTimestamp(
            for: itemId,
            version: version,
            now: now
        ) == now)
        #expect(sut.applyTransform(
            itemId: itemId,
            version: version,
            counter: 50_000,
            timestamp: retainedTimestamp,
            transform: transform
        ))

        // When
        let causalTimestamp = try #require(sut.causalTransformTimestamp(
            for: itemId,
            version: version,
            now: now
        ))
        let appliedLocalTransform = sut.applyTransform(
            itemId: itemId,
            version: version,
            counter: 1,
            timestamp: causalTimestamp,
            transform: Self.transform(seed: 12)
        )

        // Then - the retained peer counter is irrelevant once the local event
        // has a strictly newer, bounded causal timestamp.
        #expect(causalTimestamp > retainedTimestamp)
        #expect(causalTimestamp <= now + 300)
        #expect(appliedLocalTransform)
        #expect(sut.transformState(for: itemId, version: version)?.timestamp == causalTimestamp)

        let root = SpaceRootModel.testRoot()
        #expect(root.gameController.spaceGameModel.applyTransform(
            itemId: itemId,
            version: version,
            counter: 2,
            timestamp: causalTimestamp,
            transform: Self.transform(seed: 12)
        ))
        let replay = try #require(root.gameController.latestSpaceTransformReplay(
            for: itemId,
            version: version
        ))
        #expect(replay.timestamp == causalTimestamp)
        #expect(Self.decodedTransform(replay.data) == Self.transform(seed: 12))

        // A retained clock exactly at the admission boundary cannot be safely
        // advanced yet; returning nil avoids manufacturing an invalid future event.
        #expect(sut.applyTransform(
            itemId: saturatedItemId,
            version: version,
            counter: 1,
            timestamp: now + 300,
            transform: transform
        ))
        #expect(sut.causalTransformTimestamp(
            for: saturatedItemId,
            version: version,
            now: now
        ) == nil)
    }

    @Test("Legacy Space transform replay adopts the requested asset baseline")
    func legacyTransformReplayAdoptsRequestedBaseline() throws {
        // Given
        let root = SpaceRootModel.testRoot()
        let sut = root.gameController
        let itemId = UUID()
        let requestedVersion = 71
        let timestamp: TimeInterval = 2_500
        let transform = Self.transform(seed: 13)
        #expect(sut.applySpaceTransform(
            data: Self.transformData(itemId: itemId, version: 0, transform: transform),
            counter: 3,
            timestamp: timestamp
        ))

        // When
        let replay = try #require(sut.latestSpaceTransformReplay(
            for: itemId,
            version: requestedVersion
        ))
        let wildcardReplay = try #require(sut.latestSpaceTransformReplay(
            for: itemId,
            version: 0
        ))

        // Then
        #expect(replay.data.effectiveAssetVersion == requestedVersion)
        #expect(replay.timestamp == timestamp)
        #expect(Self.decodedTransform(replay.data) == transform)
        #expect(wildcardReplay.data.effectiveAssetVersion == 0)
    }

    @Test("Reset clears Space reports and every retained transform")
    func resetClearsReportsAndTransforms() async throws {
        // Given
        let root = SpaceRootModel.testRoot()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let masterId = UUID()
        let playerId = UUID()
        let firstSpaceId = UUID()
        let secondSpaceId = UUID()

        sut.setMasterVersion(itemId: firstSpaceId, version: 41, masterId: masterId)
        sut.markSpaceAvailable(
            itemId: firstSpaceId,
            version: 41,
            for: [playerId],
            masterId: masterId
        )
        #expect(sut.applySpaceTransform(
            data: Self.transformData(
                itemId: firstSpaceId,
                version: 41,
                transform: Self.transform(seed: 5)
            ),
            counter: 1,
            timestamp: 0
        ))
        #expect(sut.applySpaceTransform(
            data: Self.transformData(
                itemId: secondSpaceId,
                version: 42,
                transform: Self.transform(seed: 6)
            ),
            counter: 2,
            timestamp: 0
        ))
        sut.spaceGameModel.openSpace = true

        // When
        sut.resetGameState()

        // Then
        #expect(!sut.spaceGameModel.openSpace)
        #expect(sut.spaceGameModel.playerVersions.isEmpty)
        #expect(sut.spaceGameModel.transformStates.isEmpty)
        #expect(sut.latestSpaceTransform(for: firstSpaceId, version: 41) == nil)
        #expect(sut.latestSpaceTransform(for: secondSpaceId, version: 42) == nil)
    }
}

private extension GameControllerTests {
    static func spaceListData(_ request: SpaceListRequest) -> NetworkCodableDataType {
        NetworkCodableDataType(
            id: UUID(),
            type: .space,
            version: 0,
            data: request.encodeData()
        )
    }

    static func transform(seed: Float) -> SpaceTransformModel {
        SpaceTransformModel(
            position: SIMD3<Float>(seed, seed + 1, seed + 2),
            scale: SIMD3<Float>(repeating: seed + 1),
            orientation: simd_quatf(angle: seed / 10, axis: [0, 1, 0])
        )
    }

    static func transformData(
        itemId: UUID,
        version: Int,
        transform: SpaceTransformModel
    ) -> NetworkCodableDataType {
        NetworkCodableDataType(
            id: itemId,
            type: .space,
            version: version,
            data: transform.encodeData()
        )
    }

    static func decodedTransform(_ data: NetworkCodableDataType?) -> SpaceTransformModel? {
        SpaceTransformModel.decodeData(of: data?.data)
    }
}

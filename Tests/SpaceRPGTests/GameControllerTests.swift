// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

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
            counter: 4
        )
        let appliedSecond = sut.applySpaceTransform(
            data: Self.transformData(
                itemId: secondSpaceId,
                version: 22,
                transform: secondTransform
            ),
            counter: 5
        )
        let appliedNewerFirst = sut.applySpaceTransform(
            data: Self.transformData(
                itemId: firstSpaceId,
                version: 22,
                transform: newerFirstTransform
            ),
            counter: 6
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

        #expect(sut.applySpaceTransform(data: currentData, counter: 8))

        // When
        let duplicateApplied = sut.applySpaceTransform(
            data: Self.transformData(itemId: itemId, version: 31, transform: nextTransform),
            counter: 8
        )
        let staleApplied = sut.applySpaceTransform(
            data: Self.transformData(itemId: itemId, version: 31, transform: nextTransform),
            counter: 7
        )
        let legacyAppliedAfterSequencedState = sut.applySpaceTransform(
            data: Self.transformData(itemId: itemId, version: 31, transform: nextTransform),
            counter: 0
        )
        let negativeApplied = sut.applySpaceTransform(
            data: Self.transformData(itemId: itemId, version: 31, transform: nextTransform),
            counter: -1
        )
        let malformedApplied = sut.applySpaceTransform(
            data: NetworkCodableDataType(
                id: itemId,
                type: .space,
                version: 31,
                data: Data("not a transform".utf8)
            ),
            counter: 50
        )
        let wrongModuleApplied = sut.applySpaceTransform(
            data: NetworkCodableDataType(
                id: itemId,
                type: .photo,
                version: 31,
                data: nextTransform.encodeData()
            ),
            counter: 50
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
            counter: 9
        )

        // Then
        #expect(nextApplied)
        #expect(Self.decodedTransform(sut.latestSpaceTransform(for: itemId, version: 31)) == nextTransform)
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
            counter: 1
        ))
        #expect(sut.applySpaceTransform(
            data: Self.transformData(
                itemId: secondSpaceId,
                version: 42,
                transform: Self.transform(seed: 6)
            ),
            counter: 2
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
            yaw: seed / 10,
            pitch: seed / 20
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

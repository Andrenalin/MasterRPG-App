// @copyright André Trettin

#if canImport(Testing)
import AdventureRPG
import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import GameRPG
@testable import PhotoRPG

@Suite("Photo availability message sequencing", .serialized)
@MainActor
struct PhotoMessageFlowTests {
    enum DeferredRevealReset: CaseIterable, Sendable {
        case lostConnection
        case stop
    }

    @Test("Master ignores stale, duplicate, negative, and malformed photo lists")
    func masterIgnoresInvalidPhotoListSequence() async throws {
        let env = try await Self.preparedEnvironment()
        let photoId = try #require(env.masterRoot.photoRoot.itemController.itemDataModel.items.first)
        let version = await env.masterRoot.photoRoot.gameController.networkVersion(for: photoId)

        _ = try await env.master.handlePhoto(
            Self.photoReport(from: env.player1Root, versions: [photoId: version], counter: 5)
        )
        let baseline = env.masterNetworkSpy.sendResponseHistory.count
        #expect(env.masterRoot.photoRoot.photoGameControllable.isPhotoAvailable(
            itemId: photoId,
            for: env.player1Config.id,
            masterId: env.masterConfig.id
        ))

        _ = try await env.master.handlePhoto(
            Self.photoReport(from: env.player1Root, versions: [:], counter: 4)
        )
        _ = try await env.master.handlePhoto(
            Self.photoReport(from: env.player1Root, versions: [:], counter: 5)
        )
        _ = try await env.master.handlePhoto(
            Self.photoReport(from: env.player1Root, versions: [:], counter: -1)
        )
        _ = try await env.master.handlePhoto(
            Self.malformedPhotoReport(from: env.player1Root, counter: 10)
        )

        #expect(env.masterNetworkSpy.sendResponseHistory.count == baseline)
        #expect(env.masterRoot.photoRoot.photoGameControllable.isPhotoAvailable(
            itemId: photoId,
            for: env.player1Config.id,
            masterId: env.masterConfig.id
        ))

        // The malformed packet did not reserve counter 10, so the next valid
        // counter after 5 is still accepted and replaces this player's report.
        _ = try await env.master.handlePhoto(
            Self.photoReport(from: env.player1Root, versions: [:], counter: 6)
        )
        #expect(env.masterNetworkSpy.sendResponseHistory.count == baseline + 1)
        #expect(!env.masterRoot.photoRoot.photoGameControllable.isPhotoAvailable(
            itemId: photoId,
            for: env.player1Config.id,
            masterId: env.masterConfig.id
        ))
    }

    @Test("Player ignores stale authoritative photo lists and malformed packets do not advance sequence")
    func playerIgnoresInvalidAuthoritativePhotoListSequence() async throws {
        let env = try await MultiConnectionTestEnvironment.create()
        let photoId = UUID()
        let version = 27
        let players = [
            photoId: [
                env.masterConfig.id: version,
                env.player1Config.id: version
            ]
        ]

        _ = try await env.player1.handlePhoto(
            Self.authoritativePhotoList(from: env.masterRoot, counter: 5, list: [photoId: version], players: players)
        )
        _ = try await env.player1.handlePhoto(
            Self.authoritativePhotoList(from: env.masterRoot, counter: 4, list: [:], players: [:])
        )
        _ = try await env.player1.handlePhoto(
            Self.authoritativePhotoList(from: env.masterRoot, counter: 5, list: [:], players: [:])
        )
        _ = try await env.player1.handlePhoto(
            Self.malformedAuthoritativePhotoList(from: env.masterRoot, counter: 10)
        )

        #expect(env.player1Root.photoRoot.photoGameControllable.masterVersion(
            for: photoId,
            masterId: env.masterConfig.id
        ) == version)
        #expect(env.player1Root.photoRoot.photoGameControllable.isPhotoAvailable(
            itemId: photoId,
            for: env.player1Config.id,
            masterId: env.masterConfig.id
        ))

        // Counter 10 was malformed and therefore not recorded.
        _ = try await env.player1.handlePhoto(
            Self.authoritativePhotoList(from: env.masterRoot, counter: 6, list: [:], players: [:])
        )
        #expect(env.player1Root.photoRoot.photoGameControllable.masterVersion(
            for: photoId,
            masterId: env.masterConfig.id
        ) == nil)
    }

    @Test("Lost player is removed from photo reports and may report again from a reset counter")
    func lostPlayerClearsPhotoAvailabilityAndSequence() async throws {
        let env = try await Self.preparedEnvironment()
        let photoId = try #require(env.masterRoot.photoRoot.itemController.itemDataModel.items.first)
        let version = await env.masterRoot.photoRoot.gameController.networkVersion(for: photoId)
        let connectionId = ConnectionController.ID()
        let report = Self.photoReport(
            from: env.player1Root,
            versions: [photoId: version],
            counter: 8
        )

        await env.master.receivedProcess(report, connectionId: connectionId)
        #expect(env.masterRoot.photoRoot.photoGameControllable.isPhotoAvailable(
            itemId: photoId,
            for: env.player1Config.id,
            masterId: env.masterConfig.id
        ))

        await env.master.lostPlayer(for: connectionId)

        #expect(!env.masterRoot.photoRoot.photoGameControllable.isPhotoAvailable(
            itemId: photoId,
            for: env.player1Config.id,
            masterId: env.masterConfig.id
        ))
        #expect(!env.masterRoot.photoRoot.gameController.gameModel.playerReport(for: photoId).contains(env.player1Config.id))

        let baseline = env.masterNetworkSpy.sendResponseHistory.count
        _ = try await env.master.handlePhoto(
            Self.photoReport(from: env.player1Root, versions: [photoId: version], counter: 1)
        )

        #expect(env.masterNetworkSpy.sendResponseHistory.count == baseline + 1)
        #expect(env.masterRoot.photoRoot.photoGameControllable.isPhotoAvailable(
            itemId: photoId,
            for: env.player1Config.id,
            masterId: env.masterConfig.id
        ))
    }

    @Test("Failed photo receipts are ignored")
    func failedPhotoReceiptIsIgnored() async throws {
        let env = try await Self.preparedEnvironment()
        let photoId = try #require(env.masterRoot.photoRoot.itemController.itemDataModel.items.first)
        let version = await env.masterRoot.photoRoot.gameController.networkVersion(for: photoId)
        let failed = env.player1Root.gameModel.outgoingMessage(
            counter: 3,
            type: .reveal,
            subType: .failed,
            asMaster: false,
            data: NetworkCodableDataType(id: photoId, type: .photo, version: version)
        )
        let baseline = env.masterNetworkSpy.sendResponseHistory.count

        _ = try await env.master.handlePhoto(failed)

        #expect(env.masterNetworkSpy.sendResponseHistory.count == baseline)
        #expect(!env.masterRoot.photoRoot.photoGameControllable.isPhotoAvailable(
            itemId: photoId,
            for: env.player1Config.id,
            masterId: env.masterConfig.id
        ))
    }

    @Test("Photo asset repair returns canonical bytes without a group rebroadcast")
    func photoAssetRepairIsRequesterOnly() async throws {
        let env = try await Self.preparedEnvironment()
        let photoId = try #require(env.masterRoot.photoRoot.itemController.itemDataModel.items.first)
        let reference = await env.masterRoot.photoRoot.gameControllable.share(id: photoId)
        let request = env.player1Root.gameModel.outgoingMessage(
            counter: 4,
            type: .reveal,
            subType: .show,
            asMaster: false,
            purpose: .assetRequest,
            data: reference
        )
        let broadcastCount = env.masterNetworkSpy.sendResponseHistory.count

        let repair = try #require(try await env.master.handlePhoto(request))

        #expect(repair.id == photoId)
        #expect(repair.effectiveAssetVersion == reference.effectiveAssetVersion)
        #expect(repair.data != nil)
        #expect(env.masterNetworkSpy.sendResponseHistory.count == broadcastCount)
    }

    @Test("Player retries a peer reveal after a matching authoritative photo list arrives")
    func playerRetriesRevealAfterAuthoritativeList() async throws {
        let env = try await Self.preparedEnvironment()
        let photoId = try #require(env.masterRoot.photoRoot.itemController.itemDataModel.items.first)
        let photoData = try await env.masterRoot.photoRoot.gameControllable.createGameData(for: photoId)
        let version = photoData.effectiveAssetVersion
        let reveal = Self.playerPhotoReveal(
            from: env.player2Config,
            masterId: env.masterConfig.id,
            counter: 3,
            data: photoData
        )
        let requestCount = env.playerNetworkSpy.calledRequest

        #expect(try await env.player1.handlePhoto(reveal) == nil)
        #expect(await env.player1Root.photoRoot.gameControllable.currentId != photoId)

        // This snapshot is authoritative but predates player 2's report. The
        // reveal remains pending until a later snapshot can prove its version.
        _ = try await env.player1.handlePhoto(
            Self.authoritativePhotoList(
                from: env.masterRoot,
                counter: 8,
                list: [photoId: version],
                players: [photoId: [env.masterConfig.id: version]]
            )
        )
        #expect(await env.player1Root.photoRoot.gameControllable.currentId != photoId)
        #expect(env.playerNetworkSpy.calledRequest == requestCount)

        _ = try await env.player1.handlePhoto(
            Self.authoritativePhotoList(
                from: env.masterRoot,
                counter: 9,
                list: [photoId: version],
                players: [
                    photoId: [
                        env.masterConfig.id: version,
                        env.player2Config.id: version
                    ]
                ]
            )
        )

        #expect(await env.player1Root.photoRoot.gameControllable.currentId == photoId)
        #expect(env.playerNetworkSpy.calledRequest == requestCount + 1)
        let acknowledgement = try #require(env.playerNetworkSpy.requestData as? GameNetworkModel)
        #expect(acknowledgement.counter == reveal.counter)
        #expect(acknowledgement.type == .reveal)
        #expect(acknowledgement.subType == .ok)
        #expect(acknowledgement.data.effectiveAssetVersion == version)
    }

    @Test("Player discards a deferred peer reveal after a concrete version mismatch")
    func playerDiscardsMismatchedDeferredReveal() async throws {
        let env = try await Self.preparedEnvironment()
        let photoId = try #require(env.masterRoot.photoRoot.itemController.itemDataModel.items.first)
        let photoData = try await env.masterRoot.photoRoot.gameControllable.createGameData(for: photoId)
        let version = photoData.effectiveAssetVersion
        let reveal = Self.playerPhotoReveal(
            from: env.player2Config,
            masterId: env.masterConfig.id,
            counter: 4,
            data: photoData
        )
        let requestCount = env.playerNetworkSpy.calledRequest

        #expect(try await env.player1.handlePhoto(reveal) == nil)
        _ = try await env.player1.handlePhoto(
            Self.authoritativePhotoList(
                from: env.masterRoot,
                counter: 10,
                list: [photoId: version],
                players: [
                    photoId: [
                        env.masterConfig.id: version,
                        env.player2Config.id: version + 1
                    ]
                ]
            )
        )

        // A later matching list cannot resurrect the reveal once the earlier
        // authoritative snapshot proved its envelope was wrong.
        _ = try await env.player1.handlePhoto(
            Self.authoritativePhotoList(
                from: env.masterRoot,
                counter: 11,
                list: [photoId: version],
                players: [
                    photoId: [
                        env.masterConfig.id: version,
                        env.player2Config.id: version
                    ]
                ]
            )
        )

        #expect(await env.player1Root.photoRoot.gameControllable.currentId != photoId)
        #expect(env.playerNetworkSpy.calledRequest == requestCount)
    }

    @Test(
        "Player lifecycle reset clears deferred peer reveals",
        arguments: DeferredRevealReset.allCases
    )
    func playerLifecycleResetClearsDeferredReveal(_ reset: DeferredRevealReset) async throws {
        let env = try await Self.preparedEnvironment()
        let photoId = try #require(env.masterRoot.photoRoot.itemController.itemDataModel.items.first)
        let photoData = try await env.masterRoot.photoRoot.gameControllable.createGameData(for: photoId)
        let version = photoData.effectiveAssetVersion
        let reveal = Self.playerPhotoReveal(
            from: env.player2Config,
            masterId: env.masterConfig.id,
            counter: 5,
            data: photoData
        )

        #expect(try await env.player1.handlePhoto(reveal) == nil)
        switch reset {
        case .lostConnection:
            await env.player1.lostConnection()
        case .stop:
            await env.player1.stop()
        }
        let requestCount = env.playerNetworkSpy.calledRequest

        _ = try await env.player1.handlePhoto(
            Self.authoritativePhotoList(
                from: env.masterRoot,
                counter: 1,
                list: [photoId: version],
                players: [
                    photoId: [
                        env.masterConfig.id: version,
                        env.player2Config.id: version
                    ]
                ]
            )
        )

        #expect(await env.player1Root.photoRoot.gameControllable.currentId != photoId)
        #expect(env.playerNetworkSpy.calledRequest == requestCount)
    }
}

private extension PhotoMessageFlowTests {
    static func preparedEnvironment() async throws -> MultiConnectionTestEnvironment {
        let env = try await MultiConnectionTestEnvironment.create()
        try await MockRoot.importTestData(
            into: env.masterRoot.adventureRoot,
            name: ResourcesDebug.photoTestData,
            itemCounter: 0
        )
        env.masterRoot.adventureRoot.startGame()
        return env
    }

    static func photoReport(
        from root: GameRoot,
        versions: [UUID: Int],
        counter: Int
    ) -> GameNetworkModel {
        root.gameModel.outgoingMessage(
            counter: counter,
            type: .update,
            subType: .photoList,
            asMaster: false,
            data: NetworkCodableDataType(
                id: UUID(),
                type: .photo,
                version: 0,
                data: PhotoListRequest(list: versions, players: [:]).encodeData()
            )
        )
    }

    static func malformedPhotoReport(from root: GameRoot, counter: Int) -> GameNetworkModel {
        root.gameModel.outgoingMessage(
            counter: counter,
            type: .update,
            subType: .photoList,
            asMaster: false,
            data: NetworkCodableDataType(
                id: UUID(),
                type: .photo,
                version: 0,
                data: Data([0xFF])
            )
        )
    }

    static func authoritativePhotoList(
        from root: GameRoot,
        counter: Int,
        list: [UUID: Int],
        players: [UUID: [UUID: Int]]
    ) -> GameNetworkModel {
        root.gameModel.outgoingMessage(
            counter: counter,
            type: .update,
            subType: .photoList,
            asMaster: true,
            data: NetworkCodableDataType(
                id: UUID(),
                type: .photo,
                version: 0,
                data: PhotoListRequest(list: list, players: players).encodeData()
            )
        )
    }

    static func malformedAuthoritativePhotoList(from root: GameRoot, counter: Int) -> GameNetworkModel {
        root.gameModel.outgoingMessage(
            counter: counter,
            type: .update,
            subType: .photoList,
            asMaster: true,
            data: NetworkCodableDataType(
                id: UUID(),
                type: .photo,
                version: 0,
                data: Data([0xFF])
            )
        )
    }

    static func playerPhotoReveal(
        from player: GameConfigModel,
        masterId: UUID,
        counter: Int,
        data: NetworkCodableDataType
    ) -> GameNetworkModel {
        GameNetworkModel(
            counter: counter,
            proxyCounter: 0,
            type: .reveal,
            subType: .show,
            masterId: masterId,
            sender: GameSenderModel(
                id: player.id,
                role: .player,
                name: "Photo Player",
                characterId: nil
            ),
            data: data
        )
    }
}
#endif

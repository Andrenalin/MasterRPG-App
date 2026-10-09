// @copyright André Trettin

#if canImport(Testing)
import AdventureRPG
import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import GameRPG
@testable import PhotoRPG
@testable import SpaceRPG

/// A player's share button follows `isSharedWithEveryone(_:)` of its own game model
/// (`GameShareView`), so that model has to converge on every device, not only on the master.
@Suite("Player share reports on player devices", .serialized)
@MainActor
struct PlayerShareReportTests {
    @Test("A 3D model contributed by a player is reported as shared on every device")
    func contributedSpaceIsReportedEverywhere() async throws {
        try await Self.verifyContributionIsReportedEverywhere(
            testData: ResourcesDebug.spaceTestData,
            listSubType: .spaceList,
            controllable: { $0.spaceRoot.gameControllable },
            sendList: { await $0.sendSpaceList() }
        )
    }

    @Test("A photo contributed by a player is reported as shared on every device")
    func contributedPhotoIsReportedEverywhere() async throws {
        try await Self.verifyContributionIsReportedEverywhere(
            testData: ResourcesDebug.photoTestData,
            listSubType: .photoList,
            controllable: { $0.photoRoot.gameControllable },
            sendList: { await $0.sendPhotoList() }
        )
    }

    @Test("A player that has not received the 3D model yet keeps its share button unconfirmed")
    func pendingPlayerIsNotReportedAsShared() async throws {
        // Given: three players joined, only the first owns the 3D model.
        let env = try await MultiConnectionTestEnvironment.create()
        try await MockRoot.importTestData(
            into: env.player1Root.adventureRoot,
            name: ResourcesDebug.spaceTestData,
            itemCounter: 0
        )
        let players = try await Self.join(env)
        let spaceId = try #require(env.player1Root.spaceRoot.itemController.itemDataModel.items.first)
        try await Self.exchangeLists(in: env, players: players, listSubType: .spaceList) {
            await $0.sendSpaceList()
        }

        // When: the master rebroadcasts the contribution and only the owner has processed it.
        let rebroadcast = try await Self.contribute(
            spaceId,
            from: env.player1Root.spaceRoot.gameControllable,
            in: env
        )
        await env.player1.receivedProcess(rebroadcast)

        // Then: the players still waiting for it do not read it as shared.
        #expect(env.player1Root.spaceRoot.gameControllable.isSharedWithEveryone(spaceId))
        #expect(!env.player2Root.spaceRoot.gameControllable.isSharedWithEveryone(spaceId))
        #expect(!env.player3Root.spaceRoot.gameControllable.isSharedWithEveryone(spaceId))
    }
}

private extension PlayerShareReportTests {
    typealias Player = (controller: PlayerController, root: GameRoot, id: UUID)

    static func verifyContributionIsReportedEverywhere(
        testData: String,
        listSubType: RPGMessageActionType,
        controllable: (GameRoot) -> any GameControllable,
        sendList: (PlayerController) async -> Void
    ) async throws {
        // Given: three players joined, only the first owns the item.
        let env = try await MultiConnectionTestEnvironment.create()
        try await MockRoot.importTestData(into: env.player1Root.adventureRoot, name: testData, itemCounter: 0)
        let players = try await join(env)
        let owner = controllable(env.player1Root)
        // A file-backed item where the fixture has one (the Space fixture's object has no file).
        let itemIds = owner.itemControllable.itemDataModel.items
        let itemId = try #require(
            itemIds.first { owner.itemControllable.itemSync(for: $0)?.fileUrl != nil } ?? itemIds.first
        )
        try await exchangeLists(in: env, players: players, listSubType: listSubType, sendList: sendList)
        for player in players {
            #expect(!controllable(player.root).isSharedWithEveryone(itemId))
        }

        // When: the owner shares it, the master adopts and rebroadcasts it, everyone confirms.
        let rebroadcast = try await contribute(itemId, from: owner, in: env)
        for player in players {
            env.playerNetworkSpy.requestData = nil
            await player.controller.receivedProcess(rebroadcast)
            let receipt = try #require(env.playerNetworkSpy.requestData as? GameNetworkModel)
            #expect(receipt.subType == .ok)
            await env.master.receivedProcess(receipt, connectionId: nil)
        }

        // Then: the master lists every player and each player's share button reads "everyone has it".
        let masterReport = Set(controllable(env.masterRoot).gameModel.playerReport(for: itemId))
        #expect(masterReport.isSuperset(of: players.map(\.id)))
        for player in players {
            #expect(controllable(player.root).isSharedWithEveryone(itemId))
        }
    }

    /// Starts the game on every device with all three players visible to each other.
    static func join(_ env: MultiConnectionTestEnvironment) async throws -> [Player] {
        let players: [Player] = [
            (env.player1, env.player1Root, env.player1Config.id),
            (env.player2, env.player2Root, env.player2Config.id),
            (env.player3, env.player3Root, env.player3Config.id)
        ]
        let roster = GameRosterModel(players: [
            env.player1Roster.players[0],
            env.player2Roster.players[0],
            env.player3Roster.players[0]
        ])
        let control = GameControlModel(controls: roster.players.map {
            SharingControlModel(id: $0.id, name: $0.name, show: true)
        })
        env.masterRoot.adventureRoot.startGame()
        env.masterRoot.gameModel.gameRoster = roster
        env.masterRoot.gameModel.gameControl = control
        await env.master.resetPlayers()
        for player in players {
            player.root.adventureRoot.startGame()
            player.root.gameModel.reset(
                gameConfig: GameConfigModel(id: player.id, state: .started, master: env.masterConfig.master),
                gameRoster: roster
            )
            player.root.gameModel.gameControl = control
            player.controller.resetPlayers()
        }
        return players
    }

    /// The join handshake: each player reports its files, the master answers everyone with the
    /// authoritative list.
    static func exchangeLists(
        in env: MultiConnectionTestEnvironment,
        players: [Player],
        listSubType: RPGMessageActionType,
        sendList: (PlayerController) async -> Void
    ) async throws {
        for player in players {
            await sendList(player.controller)
            let report = try #require(env.playerNetworkSpy.requestData as? GameNetworkModel)
            await env.master.receivedProcess(report, connectionId: nil)
            let authoritative = try #require(env.masterNetworkSpy.sendResponseData as? GameNetworkModel)
            #expect(authoritative.subType == listSubType)
            for receiver in players {
                await receiver.controller.receivedProcess(authoritative)
            }
        }
    }

    /// The first player shares `itemId`, which the master lacks. Returns the master's rebroadcast.
    static func contribute(
        _ itemId: UUID,
        from owner: any GameControllable,
        in env: MultiConnectionTestEnvironment
    ) async throws -> GameNetworkModel {
        let package = try await owner.createGameData(for: itemId)
        await env.player1.game(message: package, actionType: .generic)
        let contribution = try #require(env.playerNetworkSpy.requestData as? GameNetworkModel)
        #expect(contribution.type == .reveal)
        #expect(contribution.data.data != nil)
        // The transport fans a player's reveal out to its siblings as well.
        await env.player2.receivedProcess(contribution)
        await env.player3.receivedProcess(contribution)

        let baseline = env.masterNetworkSpy.sendResponseHistory.count
        await env.master.receivedProcess(contribution, connectionId: nil)
        let rebroadcast = try #require(
            env.masterNetworkSpy.sendResponseHistory
                .dropFirst(baseline)
                .compactMap { $0 as? GameNetworkModel }
                .first { $0.type == .reveal && $0.subType == .show }
        )
        #expect(rebroadcast.targetId == nil)
        return rebroadcast
    }
}
#endif

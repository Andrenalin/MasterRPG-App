// @copyright André Trettin

#if canImport(Testing)
import AdventureRPG
import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import AudioRPG
@testable import GameRPG
@testable import PhotoRPG
@testable import SpaceRPG

/// What a player shares and who then delivers it:
/// - a player never uploads a file the game master already has,
/// - the game master broadcasts its own copy while another player misses it,
/// - every device reads the item as shared once the master and all players have it.
///
/// A player's share button follows `isSharedWithEveryone(_:)` of its own game model
/// (`GameShareView`, the audio `SharingActionView`), so that model has to converge on every
/// device, not only on the master.
@Suite("Player sharing: who sends the file and how the reports converge", .serialized)
@MainActor
struct PlayerShareReportTests {
    @Test("An item the master lacks is uploaded once and reported as shared on every device", arguments: SharedModule.allCases)
    func contributionIsReportedEverywhere(module: SharedModule) async throws {
        // Given: three players joined, only the first owns the item.
        let env = try await MultiConnectionTestEnvironment.create()
        try await Self.importFixture(of: module, into: [env.player1Root])
        let players = try await Self.join(env)
        let itemId = try Self.sharedItemId(of: module, in: env)
        try await Self.exchangeLists(of: module, in: env, players: players)
        for player in players {
            #expect(!module.controllable(player.root).isSharedWithEveryone(itemId))
        }

        // When: the owner shares it, the master adopts and rebroadcasts it, everyone confirms.
        let contribution = try await Self.share(itemId, of: module, in: env)
        #expect(contribution.data.data != nil)
        let rebroadcast = try #require(
            try await Self.masterAnswers(to: contribution, in: env).first(where: \.isReveal)
        )
        #expect(rebroadcast.data.data != nil)
        #expect(rebroadcast.targetId == nil)
        for player in players {
            try await Self.deliver(rebroadcast, to: player, of: module, in: env, players: players)
        }

        // Then: the master lists every player and each player's share button reads "everyone has it".
        let masterReport = Set(module.controllable(env.masterRoot).gameModel.playerReport(for: itemId))
        #expect(masterReport.isSuperset(of: players.map(\.id)))
        for player in players {
            #expect(module.controllable(player.root).isSharedWithEveryone(itemId))
        }
    }

    @Test("A player that has not received the 3D model yet keeps its share button unconfirmed")
    func pendingPlayerIsNotReportedAsShared() async throws {
        // Given: three players joined, only the first owns the 3D model.
        let module = SharedModule.space
        let env = try await MultiConnectionTestEnvironment.create()
        try await Self.importFixture(of: module, into: [env.player1Root])
        let players = try await Self.join(env)
        let spaceId = try Self.sharedItemId(of: module, in: env)
        try await Self.exchangeLists(of: module, in: env, players: players)

        // When: the master rebroadcasts the contribution and only the owner has processed it.
        let contribution = try await Self.share(spaceId, of: module, in: env)
        let rebroadcast = try #require(
            try await Self.masterAnswers(to: contribution, in: env).first(where: \.isReveal)
        )
        await env.player1.receivedProcess(rebroadcast)

        // Then: the players still waiting for it do not read it as shared.
        #expect(env.player1Root.spaceRoot.gameControllable.isSharedWithEveryone(spaceId))
        #expect(!env.player2Root.spaceRoot.gameControllable.isSharedWithEveryone(spaceId))
        #expect(!env.player3Root.spaceRoot.gameControllable.isSharedWithEveryone(spaceId))
    }

    @Test("Nobody sends the file for an item the master and every player already have", arguments: SharedModule.allCases)
    func nobodySendsAFileEveryoneHas(module: SharedModule) async throws {
        // Given: the master and all three players own the item.
        let env = try await MultiConnectionTestEnvironment.create()
        try await Self.importFixture(
            of: module,
            into: [env.masterRoot, env.player1Root, env.player2Root, env.player3Root]
        )
        let players = try await Self.join(env)
        let itemId = try Self.sharedItemId(of: module, in: env)
        try await Self.exchangeLists(of: module, in: env, players: players)
        for player in players {
            #expect(module.controllable(player.root).isSharedWithEveryone(itemId))
        }
        let baseline = env.masterNetworkSpy.sendResponseHistory.count

        // When: a player shares it.
        let share = try await Self.share(itemId, of: module, in: env)
        let answers = try await Self.masterAnswers(to: share, in: env)

        // Then: the player names the item without its file, and the others show it from their copy.
        #expect(share.data.data == nil)
        let presentation = answers.first(where: \.isReveal) ?? share
        for player in players.dropFirst() {
            let receipt = try #require(
                try await Self.deliver(presentation, to: player, of: module, in: env, players: players)
            )
            #expect(receipt.subType == .ok)
        }

        // And: the master sent no file either, and the item is still shared with everyone.
        let masterFiles = env.masterNetworkSpy.sendResponseHistory
            .dropFirst(baseline)
            .compactMap { $0 as? GameNetworkModel }
            .filter { ($0.type == .reveal || $0.type == .store) && $0.data.data != nil }
        #expect(masterFiles.isEmpty)
        for player in players {
            #expect(module.controllable(player.root).isSharedWithEveryone(itemId))
        }
    }

    @Test("The master, not the sharing player, sends the file to a player that misses it", arguments: SharedModule.allCases)
    func masterDeliversToTheMissingPlayer(module: SharedModule) async throws {
        // Given: the master and two players own the item, the second player does not.
        let env = try await MultiConnectionTestEnvironment.create()
        try await Self.importFixture(of: module, into: [env.masterRoot, env.player1Root, env.player3Root])
        let players = try await Self.join(env)
        let itemId = try Self.sharedItemId(of: module, in: env)
        try await Self.exchangeLists(of: module, in: env, players: players)
        let missingPlayer = players[1]
        let missingPlayerItems = module.controllable(missingPlayer.root).itemControllable
        #expect(missingPlayerItems.itemSync(for: itemId, noGame: true) == nil)
        for player in players {
            #expect(!module.controllable(player.root).isSharedWithEveryone(itemId))
        }

        // When: a player that has it shares it.
        let share = try await Self.share(itemId, of: module, in: env)

        // Then: the player names the item to the master alone, without its file.
        #expect(share.data.data == nil)
        #expect(share.effectiveAudience == .master)

        // And: the master broadcasts its own copy, file included, to the group.
        let broadcasts = try await Self.masterAnswers(to: share, in: env).filter(\.isReveal)
        #expect(broadcasts.count == 1)
        let broadcast = try #require(broadcasts.first)
        #expect(broadcast.sender.isMaster)
        #expect(broadcast.data.data != nil)
        #expect(broadcast.targetId == nil)

        // While the missing player has not received it, neither it nor the master reads the
        // item as shared.
        for player in players where player.id != missingPlayer.id {
            try await Self.deliver(broadcast, to: player, of: module, in: env, players: players)
        }
        let master = module.controllable(env.masterRoot)
        #expect(!master.gameModel.playerReport(for: itemId).contains(missingPlayer.id))
        #expect(!master.allPlayersReported(for: itemId))
        #expect(!module.controllable(missingPlayer.root).isSharedWithEveryone(itemId))

        // When: the missing player receives the master's broadcast.
        let receipt = try #require(
            try await Self.deliver(broadcast, to: missingPlayer, of: module, in: env, players: players)
        )

        // Then: it has the item, and every device reads it as shared.
        #expect(receipt.subType == .ok)
        #expect(missingPlayerItems.itemSync(for: itemId, noGame: true) != nil)
        #expect(Set(master.gameModel.playerReport(for: itemId)).isSuperset(of: players.map(\.id)))
        #expect(master.allPlayersReported(for: itemId))
        for player in players {
            #expect(module.controllable(player.root).isSharedWithEveryone(itemId))
        }
    }
}

/// The modules a player can share from its own library.
enum SharedModule: CaseIterable, Sendable {
    case audio
    case photo
    case space
}

@MainActor
private extension SharedModule {
    var testData: String {
        switch self {
        case .audio: ResourcesDebug.audioTestData
        case .photo: ResourcesDebug.photoTestData
        case .space: ResourcesDebug.spaceTestData
        }
    }

    /// The availability list of the join handshake, also announced by the master.
    var listSubType: RPGMessageActionType {
        switch self {
        case .audio: .audioList
        case .photo: .photoList
        case .space: .spaceList
        }
    }

    func controllable(_ root: GameRoot) -> any GameControllable {
        switch self {
        case .audio: root.audioRoot.gameControllable
        case .photo: root.photoRoot.gameControllable
        case .space: root.spaceRoot.gameControllable
        }
    }

    func sendList(from player: PlayerController) async {
        switch self {
        case .audio: await player.sendAudioList()
        case .photo: await player.sendPhotoList()
        case .space: await player.sendSpaceList()
        }
    }
}

private extension GameNetworkModel {
    var isReveal: Bool { type == .reveal && subType == .show }
}

private extension PlayerShareReportTests {
    typealias Player = (controller: PlayerController, root: GameRoot, id: UUID)

    /// The same fixture gives every library the same item ids and versions.
    static func importFixture(of module: SharedModule, into roots: [GameRoot]) async throws {
        for root in roots {
            try await MockRoot.importTestData(into: root.adventureRoot, name: module.testData, itemCounter: 0)
        }
    }

    /// A file-backed item of the first player where the fixture has one (the Space fixture's
    /// object has no file).
    static func sharedItemId(of module: SharedModule, in env: MultiConnectionTestEnvironment) throws -> UUID {
        let items = module.controllable(env.player1Root).itemControllable
        let itemIds = items.itemDataModel.items
        return try #require(itemIds.first { items.itemSync(for: $0)?.fileUrl != nil } ?? itemIds.first)
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

    /// The join handshake: each player reports what it has, the master answers everyone with the
    /// authoritative list.
    static func exchangeLists(
        of module: SharedModule,
        in env: MultiConnectionTestEnvironment,
        players: [Player]
    ) async throws {
        for player in players {
            await module.sendList(from: player.controller)
            let report = try #require(env.playerNetworkSpy.requestData as? GameNetworkModel)
            let answers = try await masterAnswers(to: report, in: env)
            let authoritative = try #require(answers.last { $0.subType == module.listSubType })
            for receiver in players {
                await receiver.controller.receivedProcess(authoritative)
            }
        }
    }

    /// The first player taps share on `itemId`. Returns what it sent; a reveal to the group also
    /// reaches the other players, as the transport fans it out.
    static func share(
        _ itemId: UUID,
        of module: SharedModule,
        in env: MultiConnectionTestEnvironment
    ) async throws -> GameNetworkModel {
        let package = try await module.controllable(env.player1Root).createGameData(for: itemId)
        #expect(package.data != nil)
        env.playerNetworkSpy.requestData = nil
        await env.player1.game(message: package, actionType: .generic)
        let sent = try #require(env.playerNetworkSpy.requestData as? GameNetworkModel)
        #expect(sent.data.id == itemId)
        if sent.effectiveAudience == .group, sent.data.data != nil {
            await env.player2.receivedProcess(sent)
            await env.player3.receivedProcess(sent)
        }
        return sent
    }

    /// Everything the master sends while it processes `message`.
    static func masterAnswers(
        to message: GameNetworkModel,
        in env: MultiConnectionTestEnvironment
    ) async throws -> [GameNetworkModel] {
        let baseline = env.masterNetworkSpy.sendResponseHistory.count
        await env.master.receivedProcess(message, connectionId: nil)
        return env.masterNetworkSpy.sendResponseHistory
            .dropFirst(baseline)
            .compactMap { $0 as? GameNetworkModel }
    }

    /// `player` processes `message` and the master its answer. A report list the master
    /// announces on that answer reaches every player. Returns the player's answer.
    @discardableResult
    static func deliver(
        _ message: GameNetworkModel,
        to player: Player,
        of module: SharedModule,
        in env: MultiConnectionTestEnvironment,
        players: [Player]
    ) async throws -> GameNetworkModel? {
        env.playerNetworkSpy.requestData = nil
        await player.controller.receivedProcess(message)
        guard let answer = env.playerNetworkSpy.requestData as? GameNetworkModel else { return nil }
        for announcement in try await masterAnswers(to: answer, in: env)
            where announcement.type == .update && announcement.subType == module.listSubType {
            for receiver in players {
                await receiver.controller.receivedProcess(announcement)
            }
        }
        return answer
    }
}
#endif

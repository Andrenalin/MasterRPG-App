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
/// - the game master delivers its own copy to the player that misses it,
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
        let env = try await Self.environment(of: module, masterOwns: false, owners: [true, false, false])
        let sharer = env.players[0]
        let itemId = try Self.sharedItemId(of: module, in: sharer.root)
        for player in env.players {
            #expect(!module.controllable(player.root).isSharedWithEveryone(itemId))
        }

        // When: the owner shares it.
        try await Self.share(itemId, of: module, by: sharer)

        // Then: its file went to the master once, and the master delivered its new copy to
        // the two players that lacked it.
        let uploads = env.playerSends.filter { $0.message.data.id == itemId && $0.message.data.data != nil }
        #expect(uploads.count == 1)
        #expect(uploads.first?.connectionId == sharer.connectionId)
        let deliveries = env.masterSends.filter { $0.message.data.id == itemId && $0.message.data.data != nil }
        #expect(Set(deliveries.compactMap(\.connectionId)) == Set(env.players.dropFirst().map(\.connectionId)))

        // And: the master lists every player and each share button reads "everyone has it".
        let masterReport = Set(module.controllable(env.masterRoot).gameModel.playerReport(for: itemId))
        #expect(masterReport.isSuperset(of: env.players.map(\.id)))
        for player in env.players {
            #expect(module.controllable(player.root).isSharedWithEveryone(itemId))
        }
    }

    @Test("Nobody sends the file for an item the master and every player already have", arguments: SharedModule.allCases)
    func nobodySendsAFileEveryoneHas(module: SharedModule) async throws {
        // Given: the master and all three players own the item.
        let env = try await Self.environment(of: module, masterOwns: true, owners: [true, true, true])
        let itemId = try Self.sharedItemId(of: module, in: env.players[0].root)
        for player in env.players {
            #expect(module.controllable(player.root).isSharedWithEveryone(itemId))
        }

        // When: a player shares it.
        try await Self.share(itemId, of: module, by: env.players[0])

        // Then: no file crossed the network in either direction, and everyone confirmed the
        // master's reference from its own copy.
        #expect(env.playerSends.allSatisfy { $0.message.data.data == nil || $0.message.data.id != itemId })
        #expect(env.masterSends.allSatisfy { $0.message.data.data == nil || $0.message.data.id != itemId })
        for player in env.players {
            #expect(env.playerSends.contains {
                $0.connectionId == player.connectionId && $0.message.subType == .ok && $0.message.data.id == itemId
            })
            #expect(module.controllable(player.root).isSharedWithEveryone(itemId))
        }
    }

    @Test("The master, not the sharing player, sends the file to a player that misses it", arguments: SharedModule.allCases)
    func masterDeliversToTheMissingPlayer(module: SharedModule) async throws {
        // Given: the master and two players own the item, the second player does not.
        let env = try await Self.environment(of: module, masterOwns: true, owners: [true, false, true])
        let sharer = env.players[0]
        let missingPlayer = env.players[1]
        let itemId = try Self.sharedItemId(of: module, in: sharer.root)
        let missingPlayerItems = module.controllable(missingPlayer.root).itemControllable
        #expect(missingPlayerItems.itemSync(for: itemId, noGame: true) == nil)
        let master = module.controllable(env.masterRoot)
        #expect(!master.allPlayersReported(for: itemId))
        for player in env.players {
            #expect(!module.controllable(player.root).isSharedWithEveryone(itemId))
        }

        // When: a player that has it shares it.
        try await Self.share(itemId, of: module, by: sharer)

        // Then: the player named the item to the master, without its file.
        let share = try #require(env.playerSends.first {
            $0.connectionId == sharer.connectionId && $0.message.type == .update && $0.message.subType == .generic
        })
        #expect(share.message.data.id == itemId)
        #expect(share.message.data.data == nil)

        // And: the master sent its own copy, to the player that missed it only.
        let deliveries = env.masterSends.filter { $0.message.data.id == itemId && $0.message.data.data != nil }
        #expect(deliveries.count == 1)
        #expect(deliveries.first?.connectionId == missingPlayer.connectionId)
        #expect(deliveries.first?.message.sender.isMaster == true)

        // And: the missing player has the item, and every device reads it as shared.
        #expect(missingPlayerItems.itemSync(for: itemId, noGame: true) != nil)
        #expect(Set(master.gameModel.playerReport(for: itemId)).isSuperset(of: env.players.map(\.id)))
        #expect(master.allPlayersReported(for: itemId))
        for player in env.players {
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

    func controllable(_ root: GameRoot) -> any GameControllable {
        switch self {
        case .audio: root.audioRoot.gameControllable
        case .photo: root.photoRoot.gameControllable
        case .space: root.spaceRoot.gameControllable
        }
    }
}

private extension PlayerShareReportTests {
    /// A game master and three players over an in-memory network. The same fixture gives
    /// every library that imports it the same item ids and versions. Every player did the
    /// connect handshake, so the master and the players know who holds what.
    static func environment(
        of module: SharedModule,
        masterOwns: Bool,
        owners: [Bool]
    ) async throws -> LinkedGameEnvironment {
        let env = try await LinkedGameEnvironment.create()
        if masterOwns {
            try await env.importData(named: module.testData, into: env.masterRoot)
        }
        env.masterRoot.adventureRoot.startGame()
        for (index, owns) in owners.enumerated() {
            let player = try await env.addPlayer(named: "Player - \(index + 1)")
            if owns {
                try await env.importData(named: module.testData, into: player.root)
            }
            player.root.adventureRoot.startGame()
        }
        for player in env.players {
            await env.ready(player)
        }
        env.clearHistory()
        return env
    }

    /// A file-backed item where the fixture has one (the Space fixture's object has no file).
    static func sharedItemId(of module: SharedModule, in root: GameRoot) throws -> UUID {
        let items = module.controllable(root).itemControllable
        let itemIds = items.itemDataModel.items
        return try #require(itemIds.first { items.itemSync(for: $0)?.fileUrl != nil } ?? itemIds.first)
    }

    /// The player taps share on `itemId`.
    static func share(
        _ itemId: UUID,
        of module: SharedModule,
        by player: LinkedGameEnvironment.Player
    ) async throws {
        let controllable = module.controllable(player.root)
        if module == .audio {
            // Audio's share button names the item only; the game exports the file when the
            // master lacks it. See CODE_AUDIT_Audio2 §7.6.
            let reference = await controllable.share(id: itemId)
            #expect(reference.data == nil)
            await player.controller.game(message: reference, actionType: .generic)
            return
        }
        let package = try await controllable.createGameData(for: itemId)
        #expect(package.data != nil)
        await player.controller.game(message: package, actionType: .generic)
    }
}
#endif

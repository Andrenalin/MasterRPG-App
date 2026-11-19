// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import AdventureRPG
@testable import AudioRPG
@testable import GameRPG

/// CODE_AUDIT_TestGaps §3.2: the master's pending-audio state machine
/// (`MasterController+AudioMessages`): a play waits for the players' files, starts at its
/// deadline without the players that never answer, is replaced by a newer play or a pause, and
/// is retried a bounded number of times when its package cannot be prepared.
///
/// The deadline is never waited out: it is set far away and expired by hand
/// (`audioPlayDeadlineExpired`), and the retry delay is set to a millisecond.
@MainActor
@Suite("Audio play state machine")
struct AudioPlayStateMachineTests {
    /// A master with a ready player that holds the audio and a quiet player that never answers.
    private struct Table {
        let env: LinkedGameEnvironment
        let ready: LinkedGameEnvironment.Player
        let quiet: LinkedGameEnvironment.Player
        let audioIds: [UUID]
    }

    private static func makeTable() async throws -> Table {
        let env = try await LinkedGameEnvironment.create()
        try await env.importData(named: ResourcesDebug.audioTestData, into: env.masterRoot)
        env.masterRoot.adventureRoot.startGame()
        let ready = try await env.addPlayer(named: "Ready")
        try await env.importData(named: ResourcesDebug.audioTestData, into: ready.root)
        ready.root.adventureRoot.startGame()
        let quiet = try await env.addPlayer(named: "Quiet")
        quiet.root.adventureRoot.startGame()
        await env.ready(ready)
        await env.ready(quiet)
        env.mute(quiet)
        env.clearHistory()
        // Never reached by itself: the tests expire the deadline by hand.
        env.master.audioPlayDeadline = .seconds(600)
        let audioIds = env.masterRoot.audioRoot.itemController.itemDataModel.items
        return Table(env: env, ready: ready, quiet: quiet, audioIds: audioIds)
    }

    private static func requestPlay(_ id: UUID, on table: Table) async {
        await table.env.master.game(
            message: table.env.masterRoot.audioRoot.gameController.requestPlay(id: id),
            actionType: .playAudio
        )
        await table.env.master.waitForAudioDeliveries()
    }

    private static func playCommands(_ table: Table) -> [(connectionId: ConnectionController.ID?, message: GameNetworkModel)] {
        table.env.masterSends.filter { $0.message.subType == .playAudio }
    }

    @Test("A player that never answers does not hold the music: the deadline starts it for the others")
    func deadlineStartsThePlayWithoutTheQuietPlayer() async throws {
        // Given: the quiet player blocks the pending play.
        let table = try await Self.makeTable()
        let master = table.env.master
        let audioId = try #require(table.audioIds.last)
        await Self.requestPlay(audioId, on: table)
        #expect(Self.playCommands(table).isEmpty)
        #expect(master.gameModel.pendingAudioPlays[audioId] != nil)
        #expect(master.audioPlayDeadlineTasks.keys.contains(audioId))
        #expect(master.runningAudioPlay == nil)

        // When: the deadline passes.
        await master.audioPlayDeadlineExpired(id: audioId)

        // Then: the play runs for everyone, the quiet player is given up on and may join later.
        #expect(Self.playCommands(table).count == 1)
        #expect(Self.playCommands(table).first?.connectionId == nil)
        #expect(master.runningAudioPlay != nil)
        #expect(master.lateAudioPlayers == [table.quiet.id])
        #expect(master.gameModel.isAudioDeliveryAbandoned(itemId: audioId, playerId: table.quiet.id))
        #expect(master.gameModel.pendingAudioPlays[audioId] == nil)
        #expect(master.audioPlayDeadlineTasks.isEmpty)

        // And a deadline that fires again for the same play starts nothing twice.
        await master.audioPlayDeadlineExpired(id: audioId)
        #expect(Self.playCommands(table).count == 1)
    }

    @Test("A newer play replaces the pending one, and the old deadline starts nothing")
    func newerPlaySupersedesThePendingOne() async throws {
        // Given: a play A waits for the quiet player.
        let table = try await Self.makeTable()
        let master = table.env.master
        let ids = Array(table.audioIds.suffix(2))
        try #require(ids.count == 2 && ids[0] != ids[1], "the audio test data holds two items")
        let first = ids[0]
        let second = ids[1]
        await Self.requestPlay(first, on: table)
        #expect(master.gameModel.pendingAudioPlays[first] != nil)

        // When: the game master chooses another play.
        await Self.requestPlay(second, on: table)

        // Then: only the newer play waits, with its own deadline.
        #expect(master.gameModel.pendingAudioPlays[first] == nil)
        #expect(master.gameModel.pendingAudioPlays[second] != nil)
        #expect(Set(master.audioPlayDeadlineTasks.keys) == [second])

        // The deadline of the replaced play starts nothing; the newer one starts alone.
        await master.audioPlayDeadlineExpired(id: first)
        #expect(Self.playCommands(table).isEmpty)
        #expect(master.runningAudioPlay == nil)

        await master.audioPlayDeadlineExpired(id: second)
        #expect(Self.playCommands(table).count == 1)
        #expect(master.runningAudioPlay?.id == second)
    }

    @Test("A pause ends the running play, so a late player no longer joins it")
    func pauseEndsTheMusicALatePlayerCouldJoin() async throws {
        // Given: the play started without the quiet player, who may join it.
        let table = try await Self.makeTable()
        let master = table.env.master
        let audioId = try #require(table.audioIds.last)
        await Self.requestPlay(audioId, on: table)
        await master.audioPlayDeadlineExpired(id: audioId)
        #expect(master.lateAudioPlayers == [table.quiet.id])
        table.env.clearHistory()

        // The late player still lacks the file: joining sends nothing and keeps the chance.
        await master.joinRunningAudioPlay(playerId: table.quiet.id)
        #expect(Self.playCommands(table).isEmpty)
        #expect(master.lateAudioPlayers == [table.quiet.id])

        // When: the game master pauses.
        await master.requestAudioPlay(AudioPlayRequest(id: audioId, shouldPlay: false).command)
        table.env.clearHistory()

        // Then: nothing is running that the late player could join.
        #expect(master.runningAudioPlay == nil)
        #expect(master.lateAudioPlayers.isEmpty)
        await master.joinRunningAudioPlay(playerId: table.quiet.id)
        #expect(Self.playCommands(table).isEmpty)
    }

    @Test("A play whose package cannot be prepared is retried a bounded number of times, then dropped")
    func failedDeliveryIsRetriedAndThenDropped() async throws {
        // Given: a play for an item the master cannot export.
        let table = try await Self.makeTable()
        let master = table.env.master
        master.audioPlayRetryDelay = .milliseconds(1)
        let missingItemId = UUID()

        // When
        await master.requestAudioPlay(AudioPlayRequest(id: missingItemId, shouldPlay: true).command)

        // Then: every retry counts, and the play is dropped after the last one.
        let dropped = await awaitCondition {
            master.gameModel.pendingAudioPlays[missingItemId] == nil
        }
        #expect(dropped, "the failing play was never dropped")
        #expect(master.audioPlayRetryTasks.isEmpty)
        #expect(master.gameModel.audioPlayRetryAttempts[missingItemId] == nil)
        #expect(Self.playCommands(table).isEmpty)
        #expect(master.runningAudioPlay == nil)
    }
}
#endif

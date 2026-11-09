// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import GameRPG

/// CODE_AUDIT_Game_Shareplay §6.2: a Journal attachment is put into memory whole, so what a
/// device would refuse after the load is not loaded, and a participant's loads are budgeted.
@Suite("Journal load gate")
@MainActor
struct JournalLoadGateTests {
    private func message(from config: GameConfigModel, type: NetworkModules = .photo) -> GameNetworkModel {
        GameNetworkModel(
            counter: 3,
            proxyCounter: 0,
            type: .update,
            subType: .store,
            gameConfig: config,
            data: NetworkCodableDataType(id: UUID(), type: type, version: 1, data: nil)
        )
    }

    // MARK: Which attachments are loaded

    @Test("The game master loads a player's contribution")
    func masterLoadsPlayerFiles() async throws {
        let env = try await NetworkStoreTestEnvironment.create()

        let loads = await env.networkController.shouldLoadFile(message(from: .player))

        #expect(loads)
    }

    @Test("The game master does not load an attachment that claims to come from a game master")
    func masterRefusesMasterClaims() async throws {
        let env = try await NetworkStoreTestEnvironment.create()

        let loads = await env.networkController.shouldLoadFile(message(from: .master))

        #expect(!loads)
    }

    @Test("The game master does not load the file of an observer")
    func masterRefusesObserverFiles() async throws {
        let env = try await NetworkStoreTestEnvironment.create()
        var observer = message(from: .player)
        observer.sender.role = .observer

        let loads = await env.networkController.shouldLoadFile(observer)

        #expect(!loads)
    }

    @Test("A player does not load another player's contribution, which is for the game master")
    func playerRefusesPlayerFiles() async throws {
        let env = try await NetworkStoreTestEnvironment.create(includesMasterDelegate: false)

        let loads = await env.networkController.shouldLoadFile(message(from: .player))

        #expect(!loads)
    }

    @Test("A player loads the game master's file unless it already holds it")
    func playerLoadsMasterFilesItLacks() async throws {
        let env = try await NetworkStoreTestEnvironment.create(includesMasterDelegate: false)

        let loads = await env.networkController.shouldLoadFile(message(from: .master))

        #expect(loads)
    }

    // MARK: Limits

    @Test("The Journal limit is 100 MB for the sender and the receiver")
    func journalLimit() {
        #expect(GameLimits.fitsJournalAttachment(byteCount: 0))
        #expect(GameLimits.fitsJournalAttachment(byteCount: GameLimits.maximumMessageBytes))
        #expect(!GameLimits.fitsJournalAttachment(byteCount: GameLimits.maximumMessageBytes + 1))
        #expect(!GameLimits.fitsJournalAttachment(byteCount: -1))
    }

    @Test("A load reserves the largest size and gives back what it did not use")
    func reservationIsReleased() {
        // Given
        var budget = SharePlayInboundByteBudget()
        let sender = UUID()
        let reserve = GameLimits.maximumMessageBytes
        let now = ContinuousClock.now

        // When - five loads in flight use up the minute (512 MiB), a sixth waits.
        var admitted = 0
        for _ in 0 ..< 6 where budget.admit(reserve, from: sender, now: now) { admitted += 1 }
        #expect(admitted == 5)

        // And one load ends with 1 MB: the rest of its reservation is free again.
        budget.release(reserve - ByteUnit.megabyte, from: sender)
        let afterRelease = budget.admit(reserve, from: sender, now: now)

        // Then
        #expect(afterRelease)
    }

    @Test("Another participant is not affected by a sender's reservations")
    func budgetIsPerSender() {
        var budget = SharePlayInboundByteBudget()
        let flooder = UUID()
        let other = UUID()
        let now = ContinuousClock.now
        for _ in 0 ..< 6 { _ = budget.admit(GameLimits.maximumMessageBytes, from: flooder, now: now) }

        let admitted = budget.admit(GameLimits.maximumMessageBytes, from: other, now: now)

        #expect(admitted)
    }

    @Test("A release spans several records, newest first, and never goes below zero")
    func releaseSpansRecords() {
        var budget = SharePlayInboundByteBudget()
        let sender = UUID()
        let now = ContinuousClock.now
        _ = budget.admit(300 * ByteUnit.megabyte, from: sender, now: now)
        _ = budget.admit(100 * ByteUnit.megabyte, from: sender, now: now)

        budget.release(150 * ByteUnit.megabyte, from: sender)
        budget.release(10_000 * ByteUnit.megabyte, from: sender)

        // Everything was given back: a full minute's budget is available again.
        let admitted = budget.admit(SharePlayInboundByteBudget.bytesPerSender, from: sender, now: now)
        #expect(admitted)
    }
}
#endif

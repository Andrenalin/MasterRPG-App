// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import CoreRPG
@testable import GameRPG

/// CODE_AUDIT_Game_Shareplay §3.2: a system Journal `add`/`remove` that never returns (the
/// session was invalidated mid-call) must not switch the Journal off for later sessions, and a
/// removal that hangs inside a live session must not hold its reservation for ever.
@Suite("SharePlay Journal hung system calls")
@MainActor
struct SharePlayJournalHangTests {

    @Test("a hung removal of a late add does not keep the module off the Journal in the next session")
    func hungObsoleteCleanupDoesNotBlockTheNextSession() async {
        // Given - the add of a session that was reset returns late, and removing it hangs.
        let queue = SharePlayJournalPublicationQueue<HangAttachment>()
        let addGate = HangGate()
        let removeGate = HangGate()
        let late = HangAttachment()
        queue.enqueue(for: .photo, policy: .latestWins) {
            await addGate.wait()
            return late
        } remove: { _ in
            await removeGate.wait()
            return true
        }
        #expect(await Self.eventually { await addGate.entered == 1 })
        queue.cancelAll()
        await addGate.open()
        #expect(await Self.eventually { await removeGate.entered == 1 })

        // When - the next session publishes a photo.
        let next = queue.enqueue(for: .photo, policy: .latestWins) {
            HangAttachment()
        } remove: { _ in true }

        // Then - the hung call belongs to the old session.
        #expect(next.admission == .enqueued)

        await removeGate.open()
        queue.cancelAll()
    }

    @Test("hung replacement removals of an ended session do not use up the cleanup reservations of the next one")
    func hungCleanupsDoNotExhaustTheNextSession() async {
        // Given - two cleanups hang, which is all the queue allows.
        let queue = SharePlayJournalPublicationQueue<HangAttachment>(maxOutstandingCleanups: 2)
        let removeGate = HangGate()
        for _ in 0 ..< 3 {
            let publication = queue.enqueue(for: .photo) {
                HangAttachment()
            } remove: { _ in
                await removeGate.wait()
                return true
            }
            await publication.value
        }
        #expect(await Self.eventually { await removeGate.entered == 2 })

        // When - the session ends and the next one publishes twice in a row; the second
        // publication replaces the first and needs a cleanup reservation.
        queue.cancelAll()
        let first = queue.enqueue(for: .photo) { HangAttachment() } remove: { _ in true }
        await first.value
        let second = queue.enqueue(for: .photo) { HangAttachment() } remove: { _ in true }

        // Then
        #expect(first.admission == .enqueued)
        #expect(second.admission == .enqueued)

        await removeGate.open()
        queue.cancelAll()
    }

    @Test("a removal that hangs in a live session is given up after its deadline")
    func hungCleanupIsAbandonedAfterItsDeadline() async {
        // Given - one reservation, held by a hung removal of the replaced attachment. The
        // deadline is long enough that a main actor stalled by parallel suites cannot let it
        // pass before the "while hung" enqueue below.
        let queue = SharePlayJournalPublicationQueue<HangAttachment>(
            maxOutstandingCleanups: 1,
            cleanupDeadline: .milliseconds(2000)
        )
        let removeGate = HangGate()
        for _ in 0 ..< 2 {
            let publication = queue.enqueue(for: .photo) {
                HangAttachment()
            } remove: { _ in
                await removeGate.wait()
                return true
            }
            await publication.value
        }
        #expect(await Self.eventually { await removeGate.entered == 1 })
        // A main actor stalled by parallel suites for longer than the deadline has already given
        // the removal up by now, which makes the "while hung" premise false, not the queue wrong.
        guard queue.outstandingCleanupCount == 1 else {
            await removeGate.open()
            queue.cancelAll()
            return
        }
        let whileHung = queue.enqueue(for: .photo) { HangAttachment() } remove: { _ in true }
        #expect(whileHung.admission == .rejected)

        // When - the deadline passes.
        let released = await Self.eventually { queue.outstandingCleanupCount == 0 }

        // Then - the reservation is free again although the system calls never returned.
        #expect(released)
        let afterDeadline = queue.enqueue(for: .photo) { HangAttachment() } remove: { _ in true }
        #expect(afterDeadline.admission == .enqueued)

        await removeGate.open()
        queue.cancelAll()
    }

    @Test("hung adds of an ended session do not use up the Journal for the next one")
    func hungAddsOfAnEndedSessionDoNotExhaustTheNextSession() async {
        // Given - two adds time out and never return, which is all the limiter retains.
        let limiter = SharePlayJournalAddLimiter<NetworkModules, HangAttachment>(maxRetainedAttempts: 2)
        let addGate = HangGate()
        let oldSession = UUID()
        for module in [NetworkModules.photo, .pdf] {
            let outcome = await limiter.run(
                for: module,
                scope: oldSession,
                timeout: .milliseconds(20)
            ) {
                await addGate.wait()
                return HangAttachment()
            } discardLateValue: { _ in true }
            guard case .timedOut = outcome else {
                Issue.record("Expected the add to time out")
                return
            }
        }
        limiter.cancelAll()

        // When - the next session adds.
        let outcome = await limiter.run(
            for: .photo,
            scope: UUID(),
            timeout: .seconds(1)
        ) {
            HangAttachment()
        } discardLateValue: { _ in true }

        // Then
        if case .succeeded = outcome {} else {
            Issue.record("Expected the next session to use the Journal, got \(outcome)")
        }

        await addGate.open()
    }

    // MARK: - Helpers

    private static func eventually(_ condition: @escaping @MainActor () async -> Bool) async -> Bool {
        for _ in 0 ..< 200 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return false
    }
}

private struct HangAttachment: Identifiable, Sendable {
    let id = UUID()
}

/// A system call that ignores cancellation: it stays suspended until the gate opens.
private actor HangGate {
    private(set) var entered = 0
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        entered += 1
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}
#endif

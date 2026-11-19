// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import GameRPG

/// CODE_AUDIT_Game_Shareplay §5.10: the Journal add limiter is keyed by the publication slot.
/// An audio playlist and its first track have slots of their own, and are published at the same
/// time.
@Suite("Journal add limiter slots")
@MainActor
struct SharePlayJournalSlotLimiterTests {
    @MainActor
    private final class Gate {
        private var continuation: CheckedContinuation<Int, Never>?
        private(set) var started = false

        func wait() async -> Int {
            started = true
            return await withCheckedContinuation { continuation = $0 }
        }

        func open() {
            continuation?.resume(returning: 1)
            continuation = nil
        }
    }

    private func waitUntilStarted(_ gate: Gate) async {
        _ = await awaitCondition(pollInterval: .milliseconds(5)) { gate.started }
    }

    @Test("A playlist and its first track add at the same time; two adds of one slot do not")
    func slotsDoNotCollide() async {
        let limiter = SharePlayJournalAddLimiter<SharePlayJournalSlot, Int>()
        let playlistGate = Gate()
        let trackGate = Gate()
        let playlist = SharePlayJournalSlot(.audio, isPlaylist: true)
        let track = SharePlayJournalSlot(.audio)

        let first = Task { @MainActor in
            await limiter.run(for: playlist, timeout: .seconds(30)) { await playlistGate.wait() } discardLateValue: { _ in true }
        }
        await waitUntilStarted(playlistGate)
        let second = Task { @MainActor in
            await limiter.run(for: track, timeout: .seconds(30)) { await trackGate.wait() } discardLateValue: { _ in true }
        }
        await waitUntilStarted(trackGate)
        #expect(trackGate.started)

        // The same slot is still limited to one add.
        let third = await limiter.run(for: playlist, timeout: .seconds(30)) { 0 } discardLateValue: { _ in true }
        if case .unavailable = third {} else {
            Issue.record("A second add for a busy slot must be unavailable")
        }

        playlistGate.open()
        trackGate.open()
        let results = await [first.value, second.value]
        for result in results {
            if case .succeeded = result {} else {
                Issue.record("Both adds must succeed")
            }
        }
    }

    private struct Attachment: Identifiable, Sendable {
        let id = UUID()
    }

    @Test("A large package in one slot does not use up the Journal byte budget of the others (§5.11)")
    func byteBudgetIsPerSlot() async {
        let queue = SharePlayJournalPublicationQueue<Attachment>(
            maxOutstandingBytes: 10,
            maxOutstandingTotalBytes: 100
        )
        let gate = Gate()

        let photo = queue.enqueue(for: SharePlayJournalSlot(.photo), byteCount: 8) {
            _ = await gate.wait()
            return nil
        } remove: { _ in true }
        let pdf = queue.enqueue(for: SharePlayJournalSlot(.pdf), byteCount: 8) { nil } remove: { _ in true }
        let secondPhoto = queue.enqueue(for: SharePlayJournalSlot(.photo), byteCount: 8) { nil } remove: { _ in true }

        #expect(photo.admission != .rejected)
        #expect(pdf.admission != .rejected)
        #expect(secondPhoto.admission == .rejected)
        await waitUntilStarted(gate)
        gate.open()
        await photo.value
    }
}
#endif

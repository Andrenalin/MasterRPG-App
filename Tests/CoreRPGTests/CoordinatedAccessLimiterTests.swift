// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_21 §3.8: accesses that wait for an iCloud download never hold every slot.
@Suite("Coordinated access limiter")
struct CoordinatedAccessLimiterTests {
    private func waitForWaiters(_ count: Int, in limiter: CoordinatedAccessLimiter) async throws {
        _ = await awaitCondition(pollInterval: .milliseconds(10)) { await limiter.waiterCount == count }
        #expect(await limiter.waiterCount == count)
    }

    @Test("Download waits leave one slot to local accesses")
    func downloadsLeaveOneSlot() async throws {
        let limiter = CoordinatedAccessLimiter(limit: 3)
        try await limiter.acquire(.download)
        try await limiter.acquire(.download)

        let thirdDownload = Task { try await limiter.acquire(.download) }
        try await waitForWaiters(1, in: limiter)

        // The stalled downloads do not keep a local access out.
        try await limiter.acquire(.local)
        await limiter.release(.local)
        #expect(await limiter.waiterCount == 1)

        await limiter.release(.download)
        try await thirdDownload.value
        #expect(await limiter.waiterCount == 0)
    }

    @Test("Local accesses may use every slot and hand over in arrival order")
    func localAccessesUseEverySlot() async throws {
        let limiter = CoordinatedAccessLimiter(limit: 2)
        try await limiter.acquire(.local)
        try await limiter.acquire(.local)

        let waitingDownload = Task { try await limiter.acquire(.download) }
        try await waitForWaiters(1, in: limiter)
        let waitingLocal = Task { try await limiter.acquire(.local) }
        try await waitForWaiters(2, in: limiter)

        await limiter.release(.local)
        try await waitingDownload.value
        #expect(await limiter.waiterCount == 1)

        await limiter.release(.local)
        try await waitingLocal.value
    }

    @Test("A waiting download is passed over while its share is used up")
    func localWaiterOvertakesBlockedDownload() async throws {
        let limiter = CoordinatedAccessLimiter(limit: 2)
        try await limiter.acquire(.download)
        try await limiter.acquire(.local)

        let waitingDownload = Task { try await limiter.acquire(.download) }
        try await waitForWaiters(1, in: limiter)
        let waitingLocal = Task { try await limiter.acquire(.local) }
        try await waitForWaiters(2, in: limiter)

        // The freed slot goes to the local access: the download share is still taken.
        await limiter.release(.local)
        try await waitingLocal.value
        #expect(await limiter.waiterCount == 1)

        await limiter.release(.download)
        try await waitingDownload.value
    }

    @Test("A cancelled waiter leaves the queue")
    func cancelledWaiterLeaves() async throws {
        let limiter = CoordinatedAccessLimiter(limit: 2)
        try await limiter.acquire(.local)
        try await limiter.acquire(.local)

        let waiting = Task { try await limiter.acquire(.local) }
        try await waitForWaiters(1, in: limiter)
        waiting.cancel()

        await #expect(throws: CancellationError.self) { try await waiting.value }
        #expect(await limiter.waiterCount == 0)
    }
}

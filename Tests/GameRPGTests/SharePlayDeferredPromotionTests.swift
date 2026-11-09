// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import CoreRPG
@testable import GameRPG

/// CODE_AUDIT_Game_Shareplay §5.2 and §5.17: promoting deferred deliveries.
@Suite("Deferred delivery promotion")
@MainActor
struct SharePlayDeferredPromotionTests {
    private func event(counter: Int) -> GameNetworkModel {
        GameNetworkModel(
            counter: counter,
            proxyCounter: 0,
            type: .update,
            subType: .valueUpdate,
            gameConfig: GameConfigModel(id: UUID(), state: .started, master: .empty),
            data: NetworkCodableDataType(id: UUID(), type: .value, version: 1, data: nil)
        )
    }

    /// A controller whose send queue is full of operations that wait for `gate`.
    private func controllerWithFullSendQueue(
        sessionId: UUID,
        gate: PromotionGate
    ) -> RPGSharePlayController {
        let controller = RPGSharePlayController()
        controller.sessionLifecycle.prepare(sessionId: sessionId)
        for _ in 0 ..< SharePlaySingleQueuePackageSender.maxOutstandingMessages {
            controller.addSendTask(byteCount: 0) { await gate.wait() }
        }
        return controller
    }

    @Test("A ready entry that finds the send queue full arms no timer (§5.2)")
    func readyHeadWithFullQueueDoesNotSpin() async {
        let sessionId = UUID()
        let gate = PromotionGate()
        let controller = controllerWithFullSendQueue(sessionId: sessionId, gate: gate)
        controller.deferredDeliveryQueue.enqueue(
            event(counter: 1),
            sessionId: sessionId,
            participantId: nil,
            deliveryAttempt: 1,
            retryNotBefore: .now.advanced(by: .seconds(-5))
        )

        controller.promoteDeferredDeliveries()

        // It stays queued, and nothing is armed against the deadline that has passed: the
        // completion of a running send operation promotes again.
        #expect(controller.deferredDeliveryQueue.count == 1)
        #expect(controller.deferredPromotionTask == nil)

        gate.open()
        controller.reset()
    }

    @Test("A completed send operation promotes the waiting entry (§5.2)")
    func completionPromotesTheWaitingEntry() async {
        let sessionId = UUID()
        let gate = PromotionGate()
        let controller = controllerWithFullSendQueue(sessionId: sessionId, gate: gate)
        controller.deferredDeliveryQueue.enqueue(
            event(counter: 1),
            sessionId: sessionId,
            participantId: nil,
            deliveryAttempt: 1,
            retryNotBefore: .now.advanced(by: .seconds(-5))
        )
        controller.promoteDeferredDeliveries()
        #expect(controller.deferredDeliveryQueue.count == 1)

        gate.open()
        for _ in 0 ..< 200 where controller.deferredDeliveryQueue.count > 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(controller.deferredDeliveryQueue.count == 0)
        controller.reset()
    }

    @Test("A retry that is not due yet does not hold back a ready entry behind it (§5.17)")
    func readyEntryPassesAWaitingRetry() {
        let sessionId = UUID()
        let controller = RPGSharePlayController()
        controller.sessionLifecycle.prepare(sessionId: sessionId)
        controller.deferredDeliveryQueue.enqueue(
            event(counter: 1),
            sessionId: sessionId,
            participantId: nil,
            deliveryAttempt: 1,
            retryNotBefore: .now.advanced(by: .seconds(60))
        )
        controller.deferredDeliveryQueue.enqueue(event(counter: 2), sessionId: sessionId, participantId: nil)

        controller.promoteDeferredDeliveries()

        // The ready one left the queue; the retry waits, with a timer for its back-off.
        #expect(controller.deferredDeliveryQueue.count == 1)
        #expect(controller.deferredDeliveryQueue.first?.model.counter == 1)
        #expect(controller.deferredPromotionTask != nil)
        controller.reset()
    }

    @Test("Entries of an ended session are dropped, wherever they stand in the queue")
    func endedSessionEntriesAreDropped() {
        let current = UUID()
        let ended = UUID()
        let controller = RPGSharePlayController()
        controller.sessionLifecycle.prepare(sessionId: current)
        controller.deferredDeliveryQueue.enqueue(
            event(counter: 1),
            sessionId: current,
            participantId: nil,
            deliveryAttempt: 1,
            retryNotBefore: .now.advanced(by: .seconds(60))
        )
        controller.deferredDeliveryQueue.enqueue(event(counter: 2), sessionId: ended, participantId: nil)

        controller.promoteDeferredDeliveries()

        #expect(controller.deferredDeliveryQueue.count == 1)
        #expect(controller.deferredDeliveryQueue.first?.sessionId == current)
        controller.reset()
    }

    @Test("The queue names the earliest back-off that has not passed")
    func earliestRetryIgnoresPassedAndMissingDeadlines() {
        let sessionId = UUID()
        let now = ContinuousClock().now
        var queue = SharePlayDeferredDeliveryQueue()
        queue.enqueue(event(counter: 1), sessionId: sessionId, participantId: nil)
        queue.enqueue(event(counter: 2), sessionId: sessionId, participantId: nil, deliveryAttempt: 1, retryNotBefore: now.advanced(by: .seconds(-1)))
        queue.enqueue(event(counter: 3), sessionId: sessionId, participantId: nil, deliveryAttempt: 1, retryNotBefore: now.advanced(by: .seconds(8)))
        queue.enqueue(event(counter: 4), sessionId: sessionId, participantId: nil, deliveryAttempt: 1, retryNotBefore: now.advanced(by: .seconds(3)))

        #expect(queue.earliestRetry(after: now) == now.advanced(by: .seconds(3)))
        #expect(queue.firstReady(at: now)?.entry.model.counter == 1)
    }
}

/// A suspension point a test opens by hand.
@MainActor
private final class PromotionGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let toResume = waiters
        waiters = []
        toResume.forEach { $0.resume() }
    }
}
#endif

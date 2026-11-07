// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import GameRPG

@Suite("Player state value types")
struct PlayerStateValueTypesTests {
    private func reference(_ id: UUID) -> NetworkCodableDataType {
        NetworkCodableDataType(id: id, type: .map, version: 1, data: nil)
    }

    @Test("The newest queued map state wins and an applied counter discards older ones")
    func pendingMapStateOrder() {
        var queue = PendingMapUpdateQueue()
        let mapId = UUID()
        queue.queueMapState(reference(mapId), counter: 5)
        queue.queueMapState(reference(mapId), counter: 3)
        #expect(queue.pendingMapState(for: mapId)?.counter == 5)

        queue.markMapStateApplied(itemId: mapId, counter: 5)
        #expect(queue.pendingMapState(for: mapId) == nil)
        #expect(!queue.shouldApplyMapState(itemId: mapId, counter: 4))
        #expect(queue.shouldApplyMapState(itemId: mapId, counter: 6))
        #expect(queue.shouldApplyMapState(itemId: mapId, counter: 0))
    }

    @Test("A reset forgets the queued updates and the applied counters")
    func pendingMapReset() {
        var queue = PendingMapUpdateQueue()
        let mapId = UUID()
        queue.queueMapContentUpdate(reference(mapId), counter: 2)
        queue.markMapContentApplied(itemId: mapId, counter: 9)
        queue.queueBattleRoundUpdate(reference(mapId))

        queue.reset()

        #expect(queue.pendingMapContentUpdate(for: mapId) == nil)
        #expect(queue.pendingBattleRoundUpdate(for: mapId) == nil)
        #expect(queue.shouldApplyMapContentUpdate(itemId: mapId, counter: 1))
    }

    @Test("A map is asked for once per interval")
    func mapRequestInterval() {
        var queue = PendingMapUpdateQueue()
        let mapId = UUID()
        let start = ContinuousClock.now
        let first = queue.mayRequestMap(itemId: mapId, now: start)
        let burst = queue.mayRequestMap(itemId: mapId, now: start + .seconds(1))
        let later = queue.mayRequestMap(itemId: mapId, now: start + PendingMapUpdateQueue.mapRequestInterval + .seconds(1))
        #expect(first)
        #expect(!burst)
        #expect(later)
    }

    @Test("A Character version is rejected three times, then probed at an interval")
    func characterRejections() {
        var policy = CharacterRejectionPolicy()
        let now = ContinuousClock.now
        let first = policy.record(version: 1, now: now)
        #expect(!first)
        #expect(policy.isDelayed(now: now))
        let second = policy.record(version: 1, now: now)
        let third = policy.record(version: 1, now: now)
        let announceRejected = policy.mayAnnounce(version: 1, now: now)
        #expect(!second)
        #expect(third)
        #expect(!announceRejected)

        // An edited Character has a new version and starts again.
        let announceEdited = policy.mayAnnounce(version: 2, now: now)
        #expect(announceEdited)
        #expect(policy.rejections == 0)
        #expect(!policy.isDelayed(now: now))
    }

    @Test("The retry delay grows from 5 to 20 seconds")
    func retryDelay() {
        #expect(CharacterRejectionPolicy.retryDelay(afterRejection: 1) == .seconds(5))
        #expect(CharacterRejectionPolicy.retryDelay(afterRejection: 2) == .seconds(20))
    }
}
#endif

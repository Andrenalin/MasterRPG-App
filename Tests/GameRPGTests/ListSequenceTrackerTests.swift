// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import GameRPG

@Suite("List sequence tracker")
struct ListSequenceTrackerTests {
    private let sender = UUID()

    @Test("A list is applied only when it is newer than the last one of its sender and module")
    func newerCounterWins() {
        var tracker = ListSequenceTracker()
        #expect(tracker.canApply(.audio, from: sender, counter: 1))
        tracker.record(.audio, counter: 5, from: sender)

        #expect(!tracker.canApply(.audio, from: sender, counter: 5))
        #expect(!tracker.canApply(.audio, from: sender, counter: 3))
        #expect(tracker.canApply(.audio, from: sender, counter: 6))
    }

    @Test("The modules and the senders are ordered independently")
    func independentKeys() {
        var tracker = ListSequenceTracker()
        tracker.record(.audio, counter: 9, from: sender)

        #expect(tracker.canApply(.photo, from: sender, counter: 1))
        #expect(tracker.canApply(.audio, from: UUID(), counter: 1))
    }

    @Test("Counter 0 is accepted and never recorded, a negative one is refused")
    func counterZeroAndNegative() {
        var tracker = ListSequenceTracker()
        tracker.record(.pdf, counter: 4, from: sender)
        #expect(tracker.canApply(.pdf, from: sender, counter: 0))

        tracker.record(.pdf, counter: 0, from: sender)
        #expect(!tracker.canApply(.pdf, from: sender, counter: 4))
        #expect(!tracker.canApply(.pdf, from: sender, counter: -1))
    }

    @Test("Forgetting a sender frees its counters in every module")
    func forgetSender() {
        var tracker = ListSequenceTracker()
        let other = UUID()
        for module in [NetworkModules.audio, .photo, .pdf, .space] {
            tracker.record(module, counter: 7, from: sender)
            tracker.record(module, counter: 7, from: other)
        }

        tracker.forget(senderId: sender)

        for module in [NetworkModules.audio, .photo, .pdf, .space] {
            #expect(tracker.canApply(module, from: sender, counter: 1))
            #expect(!tracker.canApply(module, from: other, counter: 7))
        }
    }

    @Test("A reset starts one module or all of them over")
    func reset() {
        var tracker = ListSequenceTracker()
        tracker.record(.audio, counter: 3, from: sender)
        tracker.record(.photo, counter: 3, from: sender)

        tracker.reset(.audio)
        #expect(tracker.canApply(.audio, from: sender, counter: 1))
        #expect(!tracker.canApply(.photo, from: sender, counter: 1))

        tracker.reset()
        #expect(tracker.canApply(.photo, from: sender, counter: 1))
    }
}
#endif

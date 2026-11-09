// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import GameRPG

@Suite("Master sequence ordering")
struct MasterSequenceGateTests {
    @Test func newerChangesPassAndReplaysDoNot() {
        var gate = MasterSequenceGate()
        let session = UUID()
        let first = gate.accept(sessionId: session, sequence: 1)
        let replay = gate.accept(sessionId: session, sequence: 1)
        let newer = gate.accept(sessionId: session, sequence: 3)
        let late = gate.accept(sessionId: session, sequence: 2)
        #expect(first)
        #expect(!replay)
        #expect(newer)
        #expect(!late)
    }

    @Test func aNewSessionStartsANewOrder() {
        var gate = MasterSequenceGate()
        let before = gate.accept(sessionId: UUID(), sequence: 9)
        let restarted = gate.accept(sessionId: UUID(), sequence: 1)
        #expect(before)
        #expect(restarted)
    }

    @Test("A late message of an earlier session cannot switch the gate back (§5.24)")
    func lateMessageOfAnEarlierSessionIsRefused() {
        var gate = MasterSequenceGate()
        let old = UUID(), current = UUID()
        let first = gate.accept(sessionId: old, sequence: 9)
        let switched = gate.accept(sessionId: current, sequence: 1)
        let lateOld = gate.accept(sessionId: old, sequence: 10)
        let next = gate.accept(sessionId: current, sequence: 2)
        gate.reset()
        let afterReset = gate.accept(sessionId: old, sequence: 11)
        #expect(first)
        #expect(switched)
        #expect(!lateOld)
        #expect(next)
        #expect(!afterReset)
    }

    @Test func resetForgetsTheOrder() {
        var gate = MasterSequenceGate()
        let session = UUID()
        _ = gate.accept(sessionId: session, sequence: 5)
        gate.reset()
        let afterReset = gate.accept(sessionId: session, sequence: 1)
        #expect(afterReset)
    }

    @Test func eachKindCountsOnItsOwn() {
        var source = MasterSequenceSource()
        let photoOne = source.next(.mapPhoto)
        let photoTwo = source.next(.mapPhoto)
        let weatherOne = source.next(.tableWeather)
        #expect(photoOne == 1)
        #expect(photoTwo == 2)
        #expect(weatherOne == 1)
    }
}
#endif

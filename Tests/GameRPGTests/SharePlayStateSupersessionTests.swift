// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import GameRPG

/// CODE_AUDIT_Game_Shareplay §5.18: a retry of a state update is dropped once a newer update of
/// the same entity was sent.
@Suite("SharePlay state supersession")
struct SharePlayStateSupersessionTests {
    private func update(subType: RPGMessageActionType, counter: Int, itemId: UUID, module: NetworkModules = .map) -> GameNetworkModel {
        GameNetworkModel(
            counter: counter,
            proxyCounter: 0,
            type: .update,
            subType: subType,
            gameConfig: GameConfigModel(id: UUID(), state: .started, master: .empty),
            data: NetworkCodableDataType(id: itemId, type: module, version: 1, data: Data([1]))
        )
    }

    @Test("A pin update is superseded by a newer one of the same pin, not by another pin's")
    func newerUpdateSupersedes() {
        var tracker = SharePlayStateSupersession()
        let pin = UUID()
        var first = update(subType: .mapPin, counter: 1, itemId: pin)
        let sender = first.sender
        var second = update(subType: .mapPin, counter: 2, itemId: pin)
        second.sender = sender
        var other = update(subType: .mapPin, counter: 3, itemId: UUID())
        other.sender = sender
        first.sender = sender

        tracker.noteSent(first, participantId: nil)
        #expect(!tracker.isSuperseded(first, participantId: nil))
        tracker.noteSent(second, participantId: nil)
        tracker.noteSent(other, participantId: nil)

        #expect(tracker.isSuperseded(first, participantId: nil))
        #expect(!tracker.isSuperseded(second, participantId: nil))
    }

    @Test("Events are never superseded: a later dice roll does not make an earlier one obsolete")
    func eventsAreNotSuperseded() {
        var tracker = SharePlayStateSupersession()
        let die = UUID()
        let first = update(subType: .generic, counter: 1, itemId: die, module: .dice)
        var second = update(subType: .generic, counter: 2, itemId: die, module: .dice)
        second.sender = first.sender

        tracker.noteSent(first, participantId: nil)
        tracker.noteSent(second, participantId: nil)

        #expect(!tracker.isSuperseded(first, participantId: nil))
    }

    @Test("A reset forgets everything")
    func reset() {
        var tracker = SharePlayStateSupersession()
        let pin = UUID()
        let first = update(subType: .battleRound, counter: 1, itemId: pin)
        var second = update(subType: .battleRound, counter: 2, itemId: pin)
        second.sender = first.sender
        tracker.noteSent(first, participantId: nil)
        tracker.noteSent(second, participantId: nil)
        tracker.reset()
        #expect(!tracker.isSuperseded(first, participantId: nil))
    }

    @Test("SharePlay activates when the device becomes eligible during a running master game (§5.20)")
    func activatesOnEligibility() {
        func decide(was: Bool, now: Bool, pending: Bool = true, session: Bool = false, activating: Bool = false) -> Bool {
            RPGSharePlayController.shouldActivateOnEligibilityChange(
                wasEligible: was,
                isEligible: now,
                hasPendingActivation: pending,
                hasSession: session,
                isActivating: activating
            )
        }
        #expect(decide(was: false, now: true))
        #expect(!decide(was: true, now: true))
        #expect(!decide(was: true, now: false))
        #expect(!decide(was: false, now: true, pending: false))
        #expect(!decide(was: false, now: true, session: true))
        #expect(!decide(was: false, now: true, activating: true))
    }
}
#endif

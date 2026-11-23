// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_28 §5.4: a register written by a newer build that this build cannot read became a
/// default stamped "now", was written back, and won the next merge on every device.
@Suite("CRDT unreadable register")
struct CRDTUnreadableRegisterTests {
    /// A register another build wrote with a value this build's `[String]` cannot decode.
    private let newerText = CRDT<[Int]>(wrappedValue: [1, 2, 3]).rawValue

    @Test("An unreadable register keeps its stored text")
    func keepsRawText() {
        let register = CRDT<[String]>(string: newerText, defaultValue: [])

        #expect(register.wrappedValue == [])
        #expect(register.rawValue == newerText, "saving would replace the newer build's value with the default")
    }

    @Test("An unreadable register never wins a merge over a real value")
    func losesMerges() {
        let unreadable = CRDT<[String]>(string: newerText, defaultValue: [])
        // Written long ago: a default stamped "now" beats it, the epoch stamp does not.
        let real = CRDT<[String]>(crdtValue: LWWRegister(["a"], actorID: "other-device", timestamp: 1_000))

        #expect(unreadable.merged(other: real).wrappedValue == ["a"])
        #expect(real.merged(other: unreadable).wrappedValue == ["a"])
    }

    @Test("A local edit replaces the unreadable text")
    func editReplaces() {
        var register = CRDT<[String]>(string: newerText, defaultValue: [])
        register.wrappedValue = ["mine"]

        #expect(register.rawValue != newerText)
        #expect(CRDT<[String]>(string: register.rawValue, defaultValue: []).wrappedValue == ["mine"])
    }

    @Test("Plain legacy text still migrates through the default")
    func plainTextMigrates() {
        let register = CRDT<[String]>(string: "a,b", defaultValue: ["a", "b"])

        #expect(register.wrappedValue == ["a", "b"])
        #expect(register.rawValue != "a,b")
    }
}

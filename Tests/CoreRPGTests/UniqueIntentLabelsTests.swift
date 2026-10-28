// @copyright André Trettin

import Testing

@testable import CoreRPG

/// CODE_AUDIT_Since_3.0.1 §5.18: Siri hands back the chosen label as a string, so with repeated
/// labels the second entry or game master could never be picked.
@Suite("Unique disambiguation labels")
struct UniqueIntentLabelsTests {
    @Test("Distinct labels stay as they are")
    func distinctUnchanged() {
        #expect(uniqueIntentLabels(["HP", "Strength (Attributes)", "iPad"]) == ["HP", "Strength (Attributes)", "iPad"])
    }

    @Test("A repeated label gets its count, in order")
    func repeatedGetsCount() {
        let labels = uniqueIntentLabels(["HP", "Mana", "HP", "HP"])
        #expect(labels == ["HP", "Mana", "HP (2)", "HP (3)"])
        #expect(Set(labels).count == labels.count)
    }

    @Test("A made-up label never collides with a real one")
    func noCollision() {
        let labels = uniqueIntentLabels(["iPad", "iPad (2)", "iPad"])
        #expect(labels == ["iPad", "iPad (2)", "iPad (3)"])
    }

    @Test("Each label still maps back to its own position")
    func mapsBack() {
        let labels = uniqueIntentLabels(["HP", "HP"])
        #expect(labels.firstIndex(of: "HP (2)") == 1)
    }
}

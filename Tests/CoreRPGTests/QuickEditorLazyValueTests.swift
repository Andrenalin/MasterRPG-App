// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_TestGaps §8.5: the box that keeps the quick editor's model from being rebuilt on
/// every parent update (`@State` keeps the first box; the `init` closure runs again each time).
@MainActor
@Suite("Quick editor lazy value")
struct QuickEditorLazyValueTests {
    private final class Counter {
        var made = 0
    }

    @Test("Nothing is made until the value is read")
    func nothingIsMadeBeforeTheFirstRead() {
        let counter = Counter()

        _ = QuickEditorLazyValue<String> { counter.made += 1; return "value" }

        #expect(counter.made == 0)
    }

    @Test("The value is made on the first read and the same value is returned afterwards")
    func madeOnceAndReused() {
        let counter = Counter()
        let box = QuickEditorLazyValue<NSObject> { counter.made += 1; return NSObject() }

        let first = box.value
        let second = box.value
        let third = box.value

        #expect(counter.made == 1)
        #expect(first === second)
        #expect(second === third)
    }

    @Test("A value that is nil-like still counts as made")
    func optionalValueIsMadeOnce() {
        let counter = Counter()
        let box = QuickEditorLazyValue<String?> { counter.made += 1; return nil }

        #expect(box.value == nil)
        #expect(box.value == nil)

        #expect(counter.made == 1, "an optional result must not be made again on every read")
    }

    @Test("Two boxes are independent")
    func boxesAreIndependent() {
        let first = QuickEditorLazyValue { "one" }
        let second = QuickEditorLazyValue { "two" }

        #expect(first.value == "one")
        #expect(second.value == "two")
    }
}
#endif

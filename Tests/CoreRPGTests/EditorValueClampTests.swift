// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_26 §5.111 / §10.17: a typed value cannot leave the editor's range.
@Suite("Editor value clamp")
struct EditorValueClampTests {
    @Test("A typed value is clamped into the editor range", arguments: [
        (value: 5_000.0, expected: 100.0),
        (value: -5_000.0, expected: 0.0),
        (value: 42.0, expected: 42.0)
    ])
    func typedValueIsClamped(value: Double, expected: Double) {
        #expect(EditorValueClamp.clamped(value, to: 0...100) == expected)
    }

    @Test("A typed whole number beyond the range does not trap")
    func hugeIntegerIsClamped() {
        #expect(EditorValueClamp.clamped(Int.max, to: 0...100) == 100)
        #expect(EditorValueClamp.clamped(Int.min, to: 0...100) == 0)
    }

    @Test("A typed value that is not finite is ignored")
    func nonFiniteIsIgnored() {
        #expect(EditorValueClamp.clamped(.nan, to: 0...100) == nil)
        #expect(EditorValueClamp.clamped(.infinity, to: 0...100) == nil)
    }
}

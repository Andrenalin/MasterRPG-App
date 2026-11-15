// @copyright André Trettin

import Foundation

/// How a value typed into a number editor is brought into the editor's range, so it can't bypass
/// the slider's limits. See CODE_AUDIT_26 §5.111 / §10.17.
enum EditorValueClamp {
    /// `value` inside `range`, or `nil` for a value that is not a finite number (the editor then
    /// keeps what it had).
    static func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double? {
        guard value.isFinite else { return nil }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// A typed whole number, which can be beyond the `Double` range's exact integers.
    static func clamped(_ value: Int, to range: ClosedRange<Double>) -> Double? {
        clamped(Double(value), to: range)
    }
}

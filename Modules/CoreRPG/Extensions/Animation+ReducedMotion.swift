// @copyright André Trettin

import SwiftUI

public extension Animation {
    /// Returns `nil` (a no-op animation) when Reduce Motion is enabled,
    /// `self` otherwise — replaces the `reduceMotion ? nil : someAnimation`
    /// ternary that was hand-copied at every call site across the app.
    /// See CODE_AUDIT §8.1 (DiceRPG audit; the duplication was repo-wide).
    func reduced(if reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : self
    }
}

public extension Optional where Wrapped == Animation {
    /// Same as `Animation.reduced(if:)`, for call sites that already carry
    /// an `Animation?` (e.g. a caller-supplied, possibly-nil animation).
    func reduced(if reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : self
    }
}

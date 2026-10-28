// @copyright André Trettin

import Foundation

/// The bounds of a dice compare value or modifier, shared by the dice model (DiceRPG) and the
/// Quick Dice slots (CoreRPG), so both accept the same values. See CODE_AUDIT_Since_3.0.1 §9.9.
public enum DiceValueLimit {
    /// Largest magnitude of a compare value or modifier; it also fits `Float` storage.
    /// See CODE_AUDIT_16 §5.4.
    public static let maximumMagnitude = 1_000_000_000
}

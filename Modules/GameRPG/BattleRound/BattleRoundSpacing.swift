// @copyright André Trettin

import CoreGraphics

/// A small, shared spacing scale for the BattleRound module's SwiftUI views,
/// covering the handful of padding/spacing values that already repeat across
/// multiple files. Bespoke, single-use fine-tuning values (e.g. one layout's
/// specific icon alignment) are deliberately left as literals — there is
/// nothing to deduplicate there, and forcing them into this scale would
/// misrepresent them as shared design decisions they aren't. See CODE_AUDIT
/// §8.4/§10.
enum BattleRoundSpacing {
    /// `2pt` — tightest inline spacing (icon-to-label gaps).
    static let extraTight: CGFloat = 2
    /// `4pt` — tight spacing between closely related elements.
    static let tight: CGFloat = 4
    /// `6pt` — compact groupings a step looser than `tight`.
    static let compact: CGFloat = 6
    /// `8pt` — the module's most common spacing/padding unit.
    static let standard: CGFloat = 8
    /// `10pt` — loosely related groups, one step past `standard`.
    static let relaxed: CGFloat = 10
    /// `12pt` — the loosest spacing shared across more than one file.
    static let loose: CGFloat = 12
}

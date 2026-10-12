// @copyright André Trettin

import CoreGraphics
import SwiftUI

/// A small, shared spacing scale for the BattleRound module's SwiftUI views,
/// covering the padding/spacing values that repeat across files. Bespoke,
/// single-use fine-tuning values (e.g. one layout's specific icon alignment)
/// are deliberately left as literals — there is nothing to deduplicate there,
/// and forcing them into this scale would misrepresent them as shared design
/// decisions they aren't.
enum BattleRoundSpacing {
    /// `2pt` — tightest inline spacing (icon-to-label gaps).
    static let extraTight: CGFloat = 2
    /// `4pt` — tight spacing between closely related elements.
    static let tight: CGFloat = 4
    /// `6pt` — compact groupings a step looser than `tight`.
    static let compact: CGFloat = 6
    /// `8pt` — the module's most common spacing/padding unit.
    static let standard: CGFloat = 8
    /// `10pt` — loosely related groups, one step past `standard`; also the
    /// padding inside a battle card.
    static let relaxed: CGFloat = 10
    /// `12pt` — the loosest spacing between elements of one group.
    static let loose: CGFloat = 12
    /// `16pt` — the screen's horizontal margin (header).
    static let wide: CGFloat = 16
    /// `24pt` — padding and corner radius of the round announcement.
    static let extraWide: CGFloat = 24
    /// `12pt` — corner radius of a battle card and of the settings panel.
    static let cardCornerRadius: CGFloat = 12
    /// `8pt` — corner radius of a row inside a panel.
    static let rowCornerRadius: CGFloat = 8
}

/// The battle round's role colors, in one place. They are the map's own pin
/// colors — the active attacker's ring is blue and a highlighted target's is
/// red on the 2D map and the 3D table — so a card reads the same as the token
/// it stands for. That is why they are fixed and not taken from the app theme.
enum BattleRoundPalette {
    /// The combatant whose turn it is.
    static let attacker: Color = .blue
    /// The targets of the attacker whose turn it is.
    static let defender: Color = .red
    /// Every participant of a card that does not have the turn.
    static let inactive: Color = .gray
}

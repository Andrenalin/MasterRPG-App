// @copyright André Trettin

import SwiftUI

/// Title, symbol and role of the "mark dead / mark alive" toggle. The name
/// row's button and the card's context menu both offer it; one definition
/// keeps their wording and icon the same.
struct BattleDeadToggle: Equatable {
    let isDead: Bool

    var title: String {
        isDead
            ? String(localized: "Mark Alive", bundle: .module)
            : String(localized: "Mark Dead", bundle: .module)
    }

    var systemImage: String {
        isDead ? "heart.fill" : "figure.fall"
    }

    /// Marking a combatant dead is the destructive direction.
    var role: ButtonRole? {
        isDead ? nil : .destructive
    }

    var tint: Color {
        isDead ? .green : .red
    }
}

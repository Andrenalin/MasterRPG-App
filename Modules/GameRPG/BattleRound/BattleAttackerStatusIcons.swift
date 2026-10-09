// @copyright André Trettin

import MapRPG
import SwiftUI

/// Marks an attacker that is a player's character. Alive/dead is shown by the
/// name row's toggle and the avatar.
struct BattleAttackerStatusIcons: View, Equatable {
    let combatant: BattleCombatant

    var body: some View {
        if combatant.isPlayer {
            Image(systemName: "person.fill")
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("Player", bundle: .module))
        }
    }
}

#Preview("Attacker status") {
    let model = BattleRoundController.preview().model

    if let card = model.cardPresentations.first {
        BattleAttackerStatusIcons(combatant: card.attacker.combatant)
        .padding()
    }
}

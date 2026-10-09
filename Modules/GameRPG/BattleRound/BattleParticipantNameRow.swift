// @copyright André Trettin

import MapRPG
import SwiftUI

/// The name line of a battle participant: the name runs to the end of the
/// row, with the alive/dead toggle at its trailing edge.
struct BattleParticipantNameRow: View {
    let combatant: BattleCombatant
    let role: BattleRoundParticipantRole
    let toggleDead: @MainActor () -> Void

    var body: some View {
        HStack(spacing: BattleRoundSpacing.extraTight) {
            BattleParticipantName(name: combatant.name)
            if role == .attacker {
                BattleAttackerStatusIcons(combatant: combatant)
                    .imageScale(.small)
                    .padding(.leading, BattleRoundSpacing.tight)
            }
            Spacer(minLength: BattleRoundSpacing.tight)
            BattleDeadToggleButton(isDead: combatant.isDead, action: toggleDead)
        }
    }
}

private struct BattleParticipantName: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.caption2)
            .lineLimit(1)
            .help(Text(verbatim: name))
    }
}

private struct BattleDeadToggleButton: View {
    let isDead: Bool
    let action: @MainActor () -> Void

    var body: some View {
        Button(
            title,
            systemImage: isDead ? "heart.fill" : "figure.fall",
            action: action
        )
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .foregroundStyle(isDead ? .green : .red)
        .help(Text(title))
    }

    private var title: String {
        isDead
            ? String(localized: "Mark Alive", bundle: .module)
            : String(localized: "Mark Dead", bundle: .module)
    }
}

#Preview("Participant name row", traits: .mockData) {
    let model = BattleRoundController.preview().model

    if let card = model.cardPresentations.first {
        BattleParticipantNameRow(
            combatant: card.attacker.combatant,
            role: .attacker,
            toggleDead: {}
        )
        .frame(width: 300)
        .padding()
    }
}

// @copyright André Trettin

import MapRPG
import SwiftUI

/// The name line of a battle participant. The wide card leads with the
/// alive/dead toggle and caps the name; the compact card lets the name run to
/// the end of the row and puts the toggle at its trailing edge.
struct BattleParticipantNameRow: View {
    let combatant: BattleCombatant
    let role: BattleRoundParticipantRole
    let isActive: Bool
    let cardLayout: BattleRoundCardLayout
    let toggleDead: @MainActor () -> Void

    // A hard-coded `maxWidth` ignored Dynamic Type entirely, risking illegible
    // truncation of a free-text combatant name at larger accessibility sizes.
    @ScaledMetric(relativeTo: .caption2) private var nameMaxWidth: CGFloat = 90

    var body: some View {
        HStack(spacing: BattleRoundSpacing.extraTight) {
            switch cardLayout {
            case .wide:
                BattleDeadToggleButton(isDead: combatant.isDead, action: toggleDead)
                BattleParticipantName(name: combatant.name)
                    .frame(maxWidth: nameMaxWidth)
            case .compact:
                BattleParticipantName(name: combatant.name)
                if role == .attacker {
                    // The trailing toggle already tells alive from dead.
                    BattleAttackerStatusIcons(
                        combatant: combatant,
                        isActive: isActive,
                        showsDead: false
                    )
                    .imageScale(.small)
                    .padding(.leading, BattleRoundSpacing.tight)
                }
                Spacer(minLength: BattleRoundSpacing.tight)
                BattleDeadToggleButton(isDead: combatant.isDead, action: toggleDead)
            }
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

#Preview("Participant name rows", traits: .mockData) {
    let model = BattleRoundController.preview().model

    if let card = model.cardPresentations.first {
        VStack(alignment: .leading) {
            BattleParticipantNameRow(
                combatant: card.attacker.combatant,
                role: .attacker,
                isActive: card.isActive,
                cardLayout: .wide,
                toggleDead: {}
            )
            BattleParticipantNameRow(
                combatant: card.attacker.combatant,
                role: .attacker,
                isActive: card.isActive,
                cardLayout: .compact,
                toggleDead: {}
            )
        }
        .frame(width: 300)
        .padding()
    }
}

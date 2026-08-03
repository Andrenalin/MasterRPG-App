// @copyright André Trettin

import CoreRPG
import MapRPG
import SwiftUI

@MainActor @Observable
final class BattleRoundCardState {
    var characterSheet: BattleCharacterSheetPresentation?

    func openCharacter(
        _ combatant: BattleCombatant,
        controller: BattleRoundController,
        showCharacter: @MainActor (BattleCombatant) -> Void
    ) {
        if let sheet = BattleCharacterSheetFactory(characterRoot: controller.root.characterRoot).presentation(for: combatant) {
            characterSheet = characterSheet?.id == sheet.id ? nil : sheet
        } else {
            showCharacter(combatant)
        }
    }
}

extension EnvironmentValues {
    @Entry var battleRoundCardLayout: BattleRoundCardLayout = .wide
}

extension BattleCombatant {
    var hasCharacter: Bool { gameCharacterId != nil || sourceCharacterId != nil }
}

struct BattleRoundCard: View {
    let presentation: BattleRoundCardPresentation
    let controller: BattleRoundController
    let showCharacter: @MainActor (BattleCombatant) -> Void
    let selectHitPoints: @MainActor (BattleCombatant) -> Void
    let selectInitiative: @MainActor (BattleCombatant) -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.battleRoundCardLayout) private var cardLayout
    @State private var cardState = BattleRoundCardState()

    var body: some View {
        Group {
            switch cardLayout {
            case .wide:
                BattleRoundWideCardLayout(
                    state: cardState,
                    presentation: presentation,
                    controller: controller,
                    showCharacter: showCharacter,
                    selectHitPoints: selectHitPoints,
                    selectInitiative: selectInitiative
                )
            case .compact:
                BattleRoundCompactCardLayout(
                    state: cardState,
                    presentation: presentation,
                    controller: controller,
                    showCharacter: showCharacter,
                    selectHitPoints: selectHitPoints,
                    selectInitiative: selectInitiative
                )
            }
        }
        .padding(10)
        #if !os(visionOS)
        .glassEffect(
            presentation.isActive
                ? .regular.tint(.blue)
                : .regular,
            in: .rect(cornerRadius: 12)
        )
        #endif
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(
                topLeadingRadius: 12,
                bottomLeadingRadius: 12
            )
            .fill(presentation.isActive ? Color.blue : .clear)
            .frame(width: 4)
            .accessibilityHidden(true)
        }
        .opacity(presentation.attacker.combatant.isDead ? 0.58 : 1)
        .animation(
            accessibilityReduceMotion ? nil : .easeInOut(duration: 0.2),
            value: presentation.isActive
        )
        .accessibilityElement(children: .contain)
        .onChange(of: presentation.isActive) { wasActive, isActive in
            // A turn moving on should never leave a stale character sheet
            // open on the card that was just active.
            guard wasActive, !isActive else { return }
            cardState.characterSheet = nil
        }
        .contextMenu {
            BattleRoundParticipantActionsMenu(
                role: .attacker,
                presentation: presentation.attacker,
                cardState: cardState,
                controller: controller,
                showCharacter: showCharacter,
                selectHitPoints: selectHitPoints
            )
            ForEach(presentation.defenders) { defender in
                BattleRoundParticipantActionsMenu(
                    role: .defender,
                    presentation: defender,
                    cardState: cardState,
                    controller: controller,
                    showCharacter: showCharacter,
                    selectHitPoints: selectHitPoints
                )
            }
        }

        if let sheet = cardState.characterSheet {
            SheetRootView(root: sheet.root, rootModel: sheet.sheet)
        }
    }
}

#Preview("Battle card", traits: .mockData) {
    let controller = BattleRoundController.preview()
    let model = controller.model

    if let card = model.cardPresentations.first {
        BattleRoundCard(
            presentation: card,
            controller: controller,
            showCharacter: { _ in },
            selectHitPoints: { _ in },
            selectInitiative: { _ in }
        )
        .padding()
        .environment(AppFocusModel())
    }
}

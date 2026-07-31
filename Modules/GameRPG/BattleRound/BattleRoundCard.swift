// @copyright André Trettin

import CoreRPG
import MapRPG
import SwiftUI

@MainActor @Observable
final class BattleRoundCardState {
    var characterSheet: BattleCharacterSheetPresentation?
}

extension EnvironmentValues {
    @Entry var battleRoundCardLayout: BattleRoundCardLayout = .wide
}

struct BattleRoundCard: View {
    let presentation: BattleRoundCardPresentation
    let controller: BattleRoundController
    let showCharacter: @MainActor (BattleCombatant) -> Void
    let selectHitPoints: @MainActor (BattleCombatant) -> Void

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
                    selectHitPoints: selectHitPoints
                )
            case .compact:
                BattleRoundCompactCardLayout(
                    state: cardState,
                    presentation: presentation,
                    controller: controller,
                    showCharacter: showCharacter,
                    selectHitPoints: selectHitPoints
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
            selectHitPoints: { _ in }
        )
        .padding()
        .environment(AppFocusModel())
    }
}

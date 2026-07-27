// @copyright André Trettin

import CoreRPG
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
    let actions: BattleRoundActions
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
                    actions: actions,
                    showCharacter: showCharacter,
                    selectHitPoints: selectHitPoints
                )
            case .compact:
                BattleRoundCompactCardLayout(
                    state: cardState,
                    presentation: presentation,
                    actions: actions,
                    showCharacter: showCharacter,
                    selectHitPoints: selectHitPoints
                )
            }
        }
        .padding(10)
        .glassEffect(
            presentation.isActive
                ? .regular.tint(.blue)
                : .regular,
            in: .rect(cornerRadius: 12)
        )
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
    let model = BattleRoundPreviewData.model()

    if let card = model.cardPresentations.first {
        BattleRoundCard(
            presentation: card,
            actions: .preview(model: model),
            showCharacter: { _ in },
            selectHitPoints: { _ in }
        )
        .padding()
    }
}

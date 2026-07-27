// @copyright André Trettin

import CoreRPG
import SwiftUI

@MainActor @Observable
final class BattleModel {
    init() {
    }
    
    var sheet: BattleCharacterSheetPresentation?
}

struct BattleRoundCard: View {
    let presentation: BattleRoundCardPresentation
    let actions: BattleRoundActions
    let showCharacter: @MainActor (BattleCombatant) -> Void
    let selectHitPoints: @MainActor (BattleCombatant) -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var model: BattleModel = .init()
    
    var body: some View {
        ViewThatFits(in: .horizontal) {
            BattleRoundWideCardLayout(
                model: model,
                presentation: presentation,
                actions: actions,
                showCharacter: showCharacter,
                selectHitPoints: selectHitPoints
            )

            BattleRoundCompactCardLayout(
                model: model,
                presentation: presentation,
                actions: actions,
                showCharacter: showCharacter,
                selectHitPoints: selectHitPoints
            )
        }
        .padding(10)
        .background(
            presentation.isActive ? Color.blue.opacity(0.14) : Color.gray.opacity(0.07),
            in: .rect(cornerRadius: 12)
        )
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(
                topLeadingRadius: 12,
                bottomLeadingRadius: 12
            )
            .fill(presentation.isActive ? .blue : .clear)
            .frame(width: 4)
            .accessibilityHidden(true)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    presentation.isActive ? Color.blue.opacity(0.65) : .clear,
                    lineWidth: 1
                )
                .accessibilityHidden(true)
        }
        .opacity(presentation.attacker.combatant.isDead ? 0.58 : 1)
        .animation(
            accessibilityReduceMotion ? nil : .easeInOut(duration: 0.2),
            value: presentation.isActive
        )
        .accessibilityElement(children: .contain)
        
        if let sheet = model.sheet {
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
        //.frame(maxWidth: 720)
        .padding()
    }
}

// @copyright André Trettin

import CoreRPG
import SwiftUI

/// A quick dice slot's dice. Tapping focuses them and rolls them for the whole game, the way a
/// dice inside a character sheet does, but fits a narrow slot: the result shows in the focused
/// dice overlay and on the slot's value button. Without a `resultCategory` the roll is shared
/// as a plain dice roll.
struct QuickDiceRollButton: View {
    let diceId: UUID
    let resultCategory: ResultCategory?

    @Environment(DiceRootModel.self) private var root
    @Environment(\.networkActions) private var networkActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let dice = root.gameController.gameItem(for: diceId)
        Button {
            withAnimation(Animation.default.reduced(if: reduceMotion)) {
                root.gameController.gameModel.focusItemIds <=> [diceId]
                root.rollAndShare(diceId: diceId, networkActions: networkActions, resultCategory: resultCategory)
            }
        } label: {
            VStack(spacing: 2) {
                (dice.dice.first ?? .empty).diceImage(for: (dice.dice.first ?? .empty).die.max)
                    .resizable()
                    .frame(width: 32, height: 32)
                Text(verbatim: dice.inlineText)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(4)
            .frame(maxWidth: .infinity)
            .foregroundStyle(.white)
            .background {
                Color.accentColor.clipShape(.rect(cornerRadius: 8))
            }
        }
        .accessibilityLabel(Text("Roll \(dice.inlineText)", bundle: .module))
        .frame(minHeight: 44)
        .borderLessTVButtonStyle()
    }
}

#Preview(traits: .mockData) {
    QuickDiceRollButton(diceId: DiceModel.previewId, resultCategory: ResultCategory(id: UUID(), module: .dice))
        .environment(DiceRootModel.preview)
        .frame(width: 80)
}

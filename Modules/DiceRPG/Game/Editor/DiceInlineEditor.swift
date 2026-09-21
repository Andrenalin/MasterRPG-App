// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DiceInlineEditor: View {
    var itemId: UUID

    @Environment(DiceRootModel.self) private var root
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(root.gameController.gameItem(for: itemId).dice) { die in
                        Button {
                            root.gameController.remove(die: die, from: itemId)
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                DieViewerView(gameController: root.gameController, diceId: itemId, die: die, withoutResult: true, resultColor: [])
                                    .padding(.vertical)

                                Image(systemName: "x.circle.fill")
                                    .offset(x: -8, y: 4)
                                    .foregroundStyle(.red)
                                    .accessibilityHidden(true)
                            }
                        }
                        .accessibilityLabel(Text("Remove \(die.die.text) die", bundle: .module))
                        .frame(minWidth: 44, minHeight: 44)
                        .borderLessTVButtonStyle()
                    }
                }
            }
            .scrollIndicators(.hidden)

            Text("Add Die from Bag", bundle: .module)
                .bold()
                .foregroundStyle(.secondary)
                .padding(.top)

            GameDiceBag { die in
                withAnimation(Animation.default.reduced(if: reduceMotion)) {
                    root.gameController.gameItem(for: itemId).dice.append(die)
                }
            }
        }
    }
}


#Preview(traits: .mockData) {
    ZStack(alignment: .topLeading) {
        DiceInlineEditor(itemId: DiceModel.previewId)
            .environment(DiceDisplayModel(isEditing: true, showPlayerDice: false, showDiceValueEditor: false))
    }
}

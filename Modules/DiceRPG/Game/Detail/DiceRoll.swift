// @copyright André Trettin

import CoreRPG
import SwiftUI

#Preview(traits: .mockData) {
    DiceRoll(itemId: DiceModel.previewId)
}

struct DiceRoll: View {
    let itemId: UUID

    @Environment(DiceRootModel.self) private var root

    @Environment(\.networkActions) var networkActions

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: valueFor(iOS: 0, macOS: 0, tvOS: 8, visionOS: 0)) {
                ForEach(root.gameController.gameItem(for: itemId).dice) { die in
                    Button {
                        Task {
                            await rollDice(die)
                        }
                    } label: {
                        VStack {
                            DieViewerView(gameController: root.gameController, diceId: itemId, die: die, withoutResult: false, resultColor: resultColor(for: die.id))
                                .padding(4)
                                .padding(.top, 4)

                            Spacer()
                        }
                        .frame(height: root.viewController.height(for: root.gameController.gameItem(for: itemId)))
                    }
                    .accessibilityLabel(Text("Roll \(die.die.text) die", bundle: .module))
                    .frame(minWidth: 44, minHeight: 44)
                    .borderLessTVButtonStyle()
                }
            }
        }
    }

    private func resultColor(for dieId: UUID) -> [Bool] {
        root.gameController.resultColor(for: dieId, itemId: itemId)
    }

    private func rollDice(_ die: DieModel) async {
        root.gameController.roll(die: die, for: itemId)
        let result = await root.gameController.createDiceResult(for: itemId, resultCategory: ResultCategory(id: itemId, module: .dice))
        networkActions?.game(result, .generic, nil)
    }
}

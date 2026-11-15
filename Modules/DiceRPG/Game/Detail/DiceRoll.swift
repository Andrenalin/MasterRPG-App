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
        // The shared path of every roll: it keeps the category the dice already carries (a
        // character's, from its sheet) instead of replacing it with a generic one.
        // See CODE_AUDIT_26 §5.34.
        root.gameController.shareRoll(of: itemId, networkActions: networkActions)
    }
}

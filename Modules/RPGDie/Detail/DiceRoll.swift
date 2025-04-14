// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct DiceRoll: View {
    let itemId: UUID

    @Environment(DiceRoot.self) private var root

    @Environment(\.networkActions) var networkActions

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: valueFor(iOS: 0, macOS: 0, tvOS: 8, visionOS: 0)) {
                ForEach(root.gameController.gameItem(for: itemId).entries) { die in
                    Button {
                        Task {
                            await roleDice(die)
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
                    .borderLessTVBottonStyle()
                }
            }
        }
    }

    private func resultColor(for dieId: UUID) -> [Bool] {
        let result = root.gameController.diceSuccess(for: itemId)
        guard let colors = result.first(where: { $0.0 == dieId }) else { return [] }
        return colors.1
    }

    private func roleDice(_ die: DieModel) async {
        root.gameController.role(die: die, for: itemId)
        let result = await root.gameController.createDiceResult(for: itemId, resultCategory: ResultCategory(id: itemId, module: .dice))
        networkActions?.game(result, .generic)
    }
}

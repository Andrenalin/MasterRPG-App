// @copyright André Trettin

import CoreRPG
import SwiftUI

struct GameDiceBag: View {
    let addAction: (DieModel) -> Void

    @Environment(DiceRootModel.self) private var root

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(root.itemController.diceBag.dice) { die in
                    Button {
                        addAction(generateDie(from: die.die))
                    } label: {
                        DieViewerView(gameController: root.gameController, diceId: UUID(), die: die, withoutResult: true, resultColor: [])
                            .padding(4)
                    }
                    .accessibilityLabel(Text("Add \(die.die.text) die", bundle: .module))
                    .frame(minWidth: 44, minHeight: 44)
                    .borderLessTVButtonStyle()
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func generateDie(from bag: RawDie) -> DieModel {
        DieModel(id: UUID(), die: bag)
    }
}

#Preview {
    GameDiceBag { _ in }
        .environment(DiceRootModel.previewWithData)
}

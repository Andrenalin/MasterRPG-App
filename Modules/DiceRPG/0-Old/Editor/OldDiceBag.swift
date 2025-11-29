// @copyright André Trettin

import CoreRPG
import SwiftUI

struct OldDiceBag: View {
    let addAction: (DieModel) -> Void

    @Environment(DiceRootModel.self) private var root

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(root.itemController.diceBag.dice) { die in
                    Button {
                        addAction(generateDie(from: die.die))
                    } label: {
                        DieViewerView(gameController: root.gameController, diceId: UUID(), die: die, withoutResult: true, resultColor: [])
                            .padding(4)
                    }
                    .borderLessTVBottonStyle()
                }
            }
        }
    }

    private func generateDie(from bag: RawDie) -> DieModel {
        DieModel(id: UUID(), die: bag)
    }
}

#Preview {
    OldDiceBag { _ in }
        .environment(DiceRootModel.previewWithData)
}

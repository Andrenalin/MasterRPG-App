// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct DiceInlineEditor: View {
    var itemId: UUID

    @Environment(DiceRootModel.self) private var root

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
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
                            }
                        }
                        .borderLessTVBottonStyle()
                    }
                }
            }

            Button {} label: {
                Text("Add Die from Bag", bundle: .module)
                    .bold()
            }
#if !os(tvOS)
            .buttonStyle(.borderedProminent)
#endif
            .opacity(0.75)
            .padding(.top)

            OldDiceBag { die in
                withAnimation { root.gameController.gameItem(for: itemId).dice.append(die) }
            }
        }
    }
}

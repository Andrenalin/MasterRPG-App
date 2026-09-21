// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DiceViewer: View {
    let model: DiceModel
    let isEditor: Bool
    
    @Environment(DiceRootModel.self) private var root
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(model.dice) { die in
                    if isEditor {
                        Button {
                            withAnimation(Animation.default.reduced(if: reduceMotion)) {
                                root.editController.remove(die: die, itemId: model.id)
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                ThumbnailDice(die: die)
                                    .padding(4)

                                Image(systemName: "x.circle.fill")
                                    .tint(.red)
                                    .offset(x: -8, y: 4)
                                    .accessibilityHidden(true)
                            }
                        }
                        .accessibilityLabel(Text("Remove \(die.die.text) die", bundle: .module))
                        .frame(minWidth: 44, minHeight: 44)
                        .borderLessTVButtonStyle()
                    } else {
                        ThumbnailDice(die: die)
                            .padding(4)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}


#Preview(traits: .mockData) {
    @Previewable @Environment(DiceRootModel.self) var root

    DiceViewer(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]), isEditor: true)
}

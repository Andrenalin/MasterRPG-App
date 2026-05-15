// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DiceBag: View {
    let model: DiceModel

    let diceBagA: [DieModel] = [.die4(color: .A), .die20(color: .A)]
    let diceBagG: [DieModel] = [.die4(color: .G), .die6(color: .G), .die8(color: .G), .die10(color: .G), .die12(color: .G), .die20(color: .G)]

    @Environment(DiceRootModel.self) private var root

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack {
                HStack(spacing: 8) {
                    diceBagView(for: diceBagA)
                }
                HStack(spacing: 8) {
                    diceBagView(for: diceBagG)
                }
            }
        }
    }

    func diceBagView(for diceBag: [DieModel]) -> some View {
        ForEach(diceBag) { die in
            Button {
                withAnimation { root.editController.add(die: die, itemId: model.id) }
            } label: {
                ThumbnailDice(die: die, listDisplayModel: root.listDisplayModel)
                    .padding(4)
            }
            .borderLessTVBottonStyle()
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(DiceRootModel.self) var root
    
    DiceEditor(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]))
}

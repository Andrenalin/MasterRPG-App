// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DiceBag: View {
    let model: DiceDataModel

    let diceBagA: [DieDataModel] = [.die4(color: .A), .die20(color: .A)]
    let diceBagG: [DieDataModel] = [.die4(color: .G), .die6(color: .G), .die8(color: .G), .die10(color: .G), .die12(color: .G), .die20(color: .G)]

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

    func diceBagView(for diceBag: [DieDataModel]) -> some View {
        ForEach(diceBag) { die in
            Button {
                withAnimation { root.editController.add(die: die, to: model) }
            } label: {
                ThumbnailDice(die: die)
                    .padding(4)
            }
            .borderLessTVBottonStyle()
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [DiceDataModel]
    
    DiceBag(model: models.first!)
}

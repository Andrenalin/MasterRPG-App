// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DiceBag: View {
    let model: DiceModel

    // `static` — a fixed catalog, not per-instance data. As instance
    // properties these were rebuilt (with fresh random `UUID`s from each
    // `.dieN(color:)` call) on every `DiceBag` re-init, churning `ForEach`
    // identity on every unrelated parent redraw. See CODE_AUDIT §7.2.
    private static let diceBagA: [DieModel] = [.die4(color: .A), .die20(color: .A)]
    private static let diceBagG: [DieModel] = [.die2(color: .G), .die4(color: .G), .die6(color: .G), .die8(color: .G), .die10(color: .G), .die12(color: .G), .die20(color: .G)]

    @Environment(DiceRootModel.self) private var root
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal) {
            VStack {
                HStack(spacing: 8) {
                    diceBagView(for: Self.diceBagA)
                }
                HStack(spacing: 8) {
                    diceBagView(for: Self.diceBagG)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    func diceBagView(for diceBag: [DieModel]) -> some View {
        ForEach(diceBag) { die in
            Button {
                withAnimation(Animation.default.reduced(if: reduceMotion)) {
                    root.editController.add(die: die, itemId: model.id)
                }
            } label: {
                ThumbnailDice(die: die)
                    .padding(4)
            }
            .accessibilityLabel(Text("Add \(die.die.text) die", bundle: .module))
            .frame(minWidth: 44, minHeight: 44)
            .borderLessTVBottonStyle()
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(DiceRootModel.self) var root
    
    DiceBag(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]))
}

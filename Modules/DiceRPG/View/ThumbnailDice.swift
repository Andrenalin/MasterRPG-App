// @copyright André Trettin

import CoreRPG
import SwiftUI

struct ThumbnailDice: View {
    let die: DieModel
    var withoutResult: Bool = false
    
    @Environment(ListDisplayModel.self) private var listDisplayModel
    
    var body: some View {
        die.diceImage(for: die.die.max)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 44, height: 44)
            .rotation3DEffect(.degrees(withoutResult ? 0 : die.rotation), axis: (x: 0, y: 0, z: 1))

            .padding(4)
    }
    
    private var height: CGFloat {
        switch listDisplayModel.displayMode {
        case .compact: 48
        case .medium: 64
        default: 80
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(DiceRootModel.self) var root

    ThumbnailDice(die: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]).dice[0], withoutResult: false)
    
    ThumbnailDice(die: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[1]).dice[0], withoutResult: false)
}

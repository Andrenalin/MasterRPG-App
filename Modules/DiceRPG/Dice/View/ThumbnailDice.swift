// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct ThumbnailDice: View {
    let die: DieDataModel
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
    @Previewable @Query var models: [DiceDataModel]

    ThumbnailDice(die: models[0].dice.first!, withoutResult: false)
    
    ThumbnailDice(die: models[1].dice.first!, withoutResult: false)
}

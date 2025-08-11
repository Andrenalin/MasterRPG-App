// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct ThumbnailDice: View {
    let model: DiceDataModel
    
    @Environment(ListModel.self) private var listModel
    
    var body: some View {
        if let die = model.config.dice.first {
            die.diceImage(for: die.die.max)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: height, height: height)
                .padding(4)
        }
    }
    
    private var height: CGFloat {
        switch listModel.displayMode {
        case .compact: 48
        case .medium: 64
        default: 80
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [DiceDataModel]

    ThumbnailDice(model: models.first!)
        .environment(ListModel())
}

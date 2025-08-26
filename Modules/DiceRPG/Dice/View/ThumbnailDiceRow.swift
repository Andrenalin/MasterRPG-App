// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct ThumbnailDiceRow: View {
    let itemId: UUID
    
    @Environment(DiceRootModel.self) private var root
    
    var body: some View {
        let _ = Self._printChanges()
        if let die = model?.dice.first {
            ThumbnailDice(die: die)
        }
    }
    
    private var model: DiceConfigDataModel? {
        root.itemController.model(for: itemId)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [DiceConfigDataModel]

    ThumbnailDice(die: models[0].dice.first!, withoutResult: false)
    
    ThumbnailDice(die: models[1].dice.first!, withoutResult: false)
}

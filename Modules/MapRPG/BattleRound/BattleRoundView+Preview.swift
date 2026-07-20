// @copyright André Trettin

import SwiftUI

#Preview("Battle Round", traits: .mockData) {
    let model = BattleRoundPreviewData.model()
    BattleRoundView(model: model, actions: .preview(model: model))
}

#Preview("Battle Round Compact", traits: .mockData) {
    let model = BattleRoundPreviewData.model()
    BattleRoundView(model: model, actions: .preview(model: model))
        .frame(width: 390, height: 700)
}

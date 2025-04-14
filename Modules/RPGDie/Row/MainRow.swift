// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct MainRow: View {
    let model: DiceModel
    let isSelected: Bool
    let cacheItemListModel: CacheItemListModel

    @Environment(DiceRoot.self) private var root
    @Environment(\.gameModus) private var gameModus
    @Environment(\.networkActions) private var networkActions
    @Environment(\.showGame) private var showGame

    var body: some View {
        ItemRow(itemId: model.id, model: model, cacheItemListModel: cacheItemListModel, name: \.name, tags: \.tags, description: \.description, isSelected: isSelected, thumbnail: {
            if let die = model.entries.first {
                DieViewerView(gameController: root.gameController, diceId: model.id, die: die, withoutResult: true, resultColor: [])
            }
        }, tagAdds: {
            CategoryItemRow(category: model.category)
        }, actionBar: {
            EmptyView()
                .shareListItem(isActive: showGame && gameModus == .master, feedBackEnabled: true) {
                    Task {
                        guard let result = try? await root.gameController.createGameData(for: model.id, resultCategory: nil) else { return }
                        networkActions?.game(result, .show)
                    }
                }
        })
    }
}

#Preview {
    MainRow(model: .preview, isSelected: true, cacheItemListModel: .preview)
        .environment(DiceRoot.preview)

}

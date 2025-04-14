// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct MainRow: View {
    let model: SpaceModel
    let isSelected: Bool
    let cacheItemListModel: CacheItemListModel
    
    @Environment(SpaceRoot.self) private var root

    @Environment(\.gameModus) private var gameModus
    @Environment(\.networkActions) private var networkActions
    @Environment(\.sharingFeatureActions) private var sharingFeatureActions
    @Environment(\.showGame) private var showGame

    var body: some View {
        ItemRow(itemId: model.id, model: model, cacheItemListModel: cacheItemListModel, name: \.name, tags: \.tags, description: \.description, isSelected: isSelected, thumbnail: {
            ThumbnailItem(model: model)
        }, tagAdds: {
            CategoryItemRow(category: model.category)
        }, actionBar: {
            EmptyView()
                .shareListItem(isActive: canShareSpace, feedBackEnabled: true) {
                    Task {
                        if gameModus == .master {
                            await networkActions?.shareId(root.gameController.share(id: model.id))
                        } else {
                            if let result = try? await root.gameController.createGameData(for: model.id) {
                                networkActions?.game(result, .generic)
                            }
                        }
                    }
                }
        })
    }
    
    private var canShareSpace: Bool {
        if gameModus == .player {
            let features = sharingFeatureActions.features()
            return features.spaceSharing && showGame
        } else {
            return showGame
        }
    }
}

#Preview {
    MainRow(model: .preview, isSelected: true, cacheItemListModel: .preview)
        .environment(SpaceRoot.preview)

}

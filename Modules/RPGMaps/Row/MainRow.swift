// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import RPGPhotos

struct MainRow: View {
    let model: MapModel
    let isSelected: Bool
    let cacheItemListModel: CacheItemListModel

    @Environment(MapRootModel.self) private var root
    @Environment(\.gameModus) private var gameModus
    @Environment(\.networkActions) private var networkActions
    @Environment(\.showGame) private var showGame

    var body: some View {
        ItemRow(itemId: model.id, model: model, cacheItemListModel: cacheItemListModel, name: \.name, tags: \.tags, description: \.description, isSelected: isSelected, thumbnail: {
            @Bindable var model = model
            if let photoId = model.photoId {
                root.photoRoot.viewController.thumbnailView(root: root.photoRoot, with: photoId)
            }
        }, tagAdds: {
            CategoryItemRow(category: model.category)
        }, actionBar: {
            EmptyView()
                .shareListItem(isActive: showGame && gameModus == .master, feedBackEnabled: true) {
                    Task {
                        await networkActions?.shareId(root.gameController.share(id: model.id))
                    }
                }
        })
    }
}

#Preview {
    MainRow(model: .preview, isSelected: true, cacheItemListModel: .preview)
        .environment(MapRootModel.preview)
}

// @copyright André Trettin

import CoreRPG
import SwiftUI
import PhotoRPG
import PhotoRPG

struct MainRow: View {
    let model: AdventureModel
    let isSelected: Bool
    let cacheItemListModel: CacheItemListModel

    @Environment(AdventureRootModel.self) private var root

    var body: some View {
        ItemRow(itemId: model.id, model: model, cacheItemListModel: cacheItemListModel, name: \.name, tags: \.tags, description: \.description, isSelected: isSelected) {
            if let photoId = model.photoId {
                root.photoRoot.viewController.thumbnailView(root: root.photoRoot, with: photoId)
            }
        } tagAdds: {
            CategoryItemRow(category: model.category)
        }
    }
}

#Preview {
    MainRow(model: .preview, isSelected: true, cacheItemListModel: .preview)
        .environment(AdventureRootModel.preview)
}

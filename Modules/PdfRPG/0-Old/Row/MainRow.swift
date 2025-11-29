// @copyright André Trettin

import CoreRPG
import SwiftUI

struct MainRow: View {
    let model: PdfModel
    let isSelected: Bool
    let cacheItemListModel: CacheItemListModel

    @Environment(PdfRootModel.self) private var root
    
    @Environment(\.gameModus) private var gameModus
    @Environment(\.networkActions) private var networkActions
    @Environment(\.showGame) private var showGame

    var body: some View {
        ItemRow(itemId: model.id, model: model, cacheItemListModel: cacheItemListModel, name: \.name, tags: \.tags, description: \.description, isSelected: isSelected, thumbnail: {
            ThumbnailItem(model: model)
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
        .environment(PdfRootModel.preview)

}

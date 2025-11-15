// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import RPGPhotos

struct MainRow: View {
    let model: ValueModel
    let isSelected: Bool
    let cacheItemListModel: CacheItemListModel

    @Environment(ValueRoot.self) private var root
    @Environment(\.gameModus) private var gameModus
    @Environment(\.networkActions) private var networkActions
    @Environment(\.showGame) private var showGame

    var body: some View {
        ItemRow(itemId: model.id, model: model, cacheItemListModel: cacheItemListModel, name: \.name, tags: \.tags, description: \.description, isSelected: isSelected) {
            @Bindable var model = model
            if let photoId = model.photoId {
                root.photoRoot.viewController.thumbnailView(root: root.photoRoot, with: photoId)
            }
        } tagAdds: {
            CategoryItemRow(category: model.category)
        } actionBar: {
            EmptyView()
                .shareListItem(isActive: showGame && gameModus == .master, feedBackEnabled: true) {
                    Task {
                        guard let result = try? await root.gameController.createGameData(for: model.id) else { return }
                        networkActions?.game(result, .generic)
                    }
                }
        }
    }
}

#Preview {
    MainRow(model: .preview, isSelected: true, cacheItemListModel: .preview)
        .environment(ValueRoot.preview)
}

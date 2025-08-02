// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct MainRowView: View {
    let model: AudioDataModel

    @Environment(CacheItemListModel.self) private var cacheModel
    @Environment(ListModel.self) private var listModel
    @Environment(SearchModel.self) private var searchModel
    @Environment(AudioRootModel.self) private var root

    var body: some View {
        ItemRow(itemId: model.id, model: model, cacheItemListModel: cacheModel, name: \.name, category: \.category, tags: \.tags, description: \.information, isSelected: false, collectionCategory: ItemListCategory.playlist)
            .animation(.smooth, value: listModel.displayMode)
#if !os(tvOS)
            .dropDestination(for: LinkData.self) { items, _ in
                addLinks(links: items)
            }
            .draggable(LinkData(itemId: model.id, module: AudioDataModel.typeId, name: model.name))
#endif
    }
    
    private func addLinks(links: [LinkData]) {
        links.forEach { link in
            guard link.module == AudioDataModel.typeId else { return }
            withAnimation { root.editController.addItem(itemId: link.itemId, in: model) }
        }
        
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [AudioDataModel]
    @Previewable @Environment(\.modelContext) var modelContext
    
    MainRowView(model: models[0])
        .environment(AudioRootModel(modelContext: modelContext))
        .environment(CacheItemListModel())
        .environment(SearchModel.preview(modelContext: modelContext, module: AudioDataModel.typeId))
        .environment(DeviceRotationModel())
}


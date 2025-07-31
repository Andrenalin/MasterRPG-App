// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct MainRowView: View {
    let model: PdfDataModel

    @Environment(CacheItemListModel.self) private var cacheModel
    @Environment(ListModel.self) private var listModel
    @Environment(SearchModel.self) private var searchModel
    @Environment(PdfRootModel.self) private var root

    var body: some View {
        ItemRow(itemId: model.id, model: model, cacheItemListModel: cacheModel, name: \.name, category: \.category, tags: \.tags, description: \.information, isTrailing: true, thumbnail: {
            ThumbnailRowPhotoView(cacheController: root.cacheController, model: model, isTrailing: true)
        })
        .animation(.smooth, value: listModel.displayMode)
#if !os(tvOS)
        .draggable(LinkData(itemId: model.id, module: PdfDataModel.typeId, name: model.name))
#endif
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [PdfDataModel]
    @Previewable @Environment(\.modelContext) var modelContext
    
    MainRowView(model: models[0])
        .environment(PdfRootModel(modelContext: modelContext))
        .environment(CacheItemListModel())
        .environment(SearchModel.preview(modelContext: modelContext, module: PdfDataModel.typeId))
        .environment(DeviceRotationModel())
}


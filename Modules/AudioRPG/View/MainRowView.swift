// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct MainRowView: View {
    let model: AudioDataModel

    @Environment(CacheItemListModel.self) private var cacheModel

    var body: some View {
        ItemRow(itemId: model.id, model: model, cacheItemListModel: cacheModel, isSelected: false)
#if !os(tvOS)
            .draggable(LinkData(itemId: model.id, module: AudioDataModel.typeId, name: model.name))
#endif
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [AudioDataModel]
    
    MainRowView(model: models[0])
}

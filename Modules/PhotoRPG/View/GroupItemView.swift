// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct GroupItemView: View {
    let model: PhotoDataModel

    @Environment(\.modelContext) var modelContext
    @Environment(GroupItemSelectionModel.self) var selection
    @Environment(PhotoRootModel.self) private var root

    var body: some View {
        PlainPhotoView(cacheController: root.cacheController, model: selectedModel, highResolution: false)
    }

    var selectedModel: PhotoDataModel {
        item ?? model
    }

    var item: PhotoDataModel? {
        guard let id = selection.selectedItem else { return nil }
        return PhotoDataModel.model(modelContext: modelContext, id: id)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [PhotoDataModel]
    @Previewable @Environment(\.modelContext) var modelContext

    GroupItemView(model: models[0])
        .environment(GroupItemSelectionModel())
        .environment(CacheItemListModel())
}


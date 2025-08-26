// @copyright André Trettin

import SwiftData
import SwiftUI

public struct GroupedPhotoView: View {
    public init(cacheController: any ImageCacheControllable, model: ItemDataModel) {
        self.cacheController = cacheController
        self.model = model
    }
    
    let cacheController: ImageCacheControllable
    let model: ItemDataModel

    @Environment(\.modelContext) var modelContext
    @Environment(GroupItemSelectionModel.self) var selection

    public var body: some View {
        CachePhotoView(cacheController: cacheController, model: selectedModel, highResolution: false)
    }

    var selectedModel: ItemDataModel {
        item ?? model
    }

    var item: ItemDataModel? {
        guard let id = selection.selectedItem else { return nil }
        return ItemDataModel.model(modelContext: modelContext, id: id)
    }
}

// @copyright André Trettin

import SwiftData
import SwiftUI

public struct OldGroupedPhotoView<Model: ItemDataModelable>: View where Model: ImageFileLoadable {
    public init(cacheController: any ImageCacheControllable, model: Model) {
        self.cacheController = cacheController
        self.model = model
    }
    
    let cacheController: ImageCacheControllable
    let model: Model

    @Environment(\.modelContext) var modelContext
    @Environment(GroupItemSelectionModel.self) var selection

    public var body: some View {
        PlainPhotoView(cacheController: cacheController, model: selectedModel, highResolution: false)
    }

    var selectedModel: Model {
        item ?? model
    }

    var item: Model? {
        guard let id = selection.selectedItem else { return nil }
        return Model.model(modelContext: modelContext, id: id)
    }
}

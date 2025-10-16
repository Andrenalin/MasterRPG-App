// @copyright André Trettin

import SwiftData
import SwiftUI

public struct GroupedPhotoView: View {
    public init(cacheController: any ImageCacheControllable, itemControllable: any ItemControllable, model: any ItemDataAccessable) {
        self.cacheController = cacheController
        self.itemController = itemControllable
        self.model = model
    }
    
    let cacheController: ImageCacheControllable
    let itemController: any ItemControllable
    let model: any ItemDataAccessable

    @Environment(\.modelContext) var modelContext
    @Environment(GroupItemSelectionModel.self) var selection

    public var body: some View {
        CachePhotoView(cacheController: cacheController, model: selectedModel, highResolution: false)
    }

    var selectedModel: any ItemDataAccessable {
        item ?? model
    }

    var item: (any ItemDataAccessable)? {
        guard let id = selection.selectedItem else { return nil }
        return itemController.itemOrEmpty(for: id)
    }
}

// @copyright André Trettin

import SwiftUI

public struct GroupedPhotoView: View {
    public init(cacheController: any ImageCacheControllable, itemControllable: any ItemControllable, model: (any ItemDataAccessable)?, cacheItemListModel: CacheItemListModel, highResolution: Bool = false) {
        self.cacheController = cacheController
        self.itemController = itemControllable
        self.model = model
        self.cacheItemListModel = cacheItemListModel
        self.highResolution = highResolution
    }
    
    let cacheController: ImageCacheControllable
    let itemController: any ItemControllable
    let model: (any ItemDataAccessable)?
    let cacheItemListModel: CacheItemListModel
    let highResolution: Bool

    @Environment(GroupItemSelectionModel.self) var selection

    public var body: some View {
        if let selectedModel {
            CachePhotoView(cacheController: cacheController, model: selectedModel, cacheItemListModel: cacheItemListModel, highResolution: highResolution)
                .id(selectedModel.id)
        }
    }

    var selectedModel: (any ItemDataAccessable)? {
        item ?? model
    }

    var item: (any ItemDataAccessable)? {
        guard let id = selection.selectedItem else { return nil }
        return itemController.itemSync(for: id)
    }
}

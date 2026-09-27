// @copyright André Trettin

import SwiftUI

public struct GroupedPhotoView: View {
    public init(cacheController: any ImageCacheControllable, itemControllable: any ItemControllable, model: (any ItemDataAccessible)?, highResolution: Bool = false) {
        self.cacheController = cacheController
        self.itemController = itemControllable
        self.model = model
        self.highResolution = highResolution
    }
    
    let cacheController: ImageCacheControllable
    let itemController: any ItemControllable
    let model: (any ItemDataAccessible)?
    let highResolution: Bool

    @Environment(GroupItemSelectionModel.self) var selection

    public var body: some View {
        if let selectedModel {
            CachePhotoView(cacheController: cacheController, model: selectedModel, highResolution: highResolution)
                .id(selectedModel.id)
        }
    }

    var selectedModel: (any ItemDataAccessible)? {
        item ?? model
    }

    var item: (any ItemDataAccessible)? {
        guard let id = selection.selectedItem else { return nil }
        return itemController.itemSync(for: id)
    }
}

#Preview {
    GroupedPhotoView(
        cacheController: FakeImageCacheController(),
        itemControllable: FakeItemController.fake,
        model: nil
    )
    .environment(GroupItemSelectionModel())
}

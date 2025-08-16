// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct LinkRootView: View {
    let isInspector: Bool
    @Environment(AudioRootModel.self) private var root
    @Query(filter: #Predicate<AudioDataModel>{ $0.displayState == 0 }, sort: \AudioDataModel.name, animation: .smooth) private var items: [AudioDataModel]
    
    var body: some View {
        LinkItemListView(items: items, parentModel: selectedModel, isInspector: isInspector) { itemId in
            if let model = root.itemController.modelSync(for: itemId) {
                MainRowView(model: model)
            }
        }
        .environment(root.listModel)
        .environment(root.listDisplayModel)
        .environment(root.newSearchModel())
        .environment(DeviceRotationModel())
        .environment(CacheItemListModel())
    }
    
    var selectedModel: AudioDataModel? {
        guard let itemId = root.currentSelectedItemId else { return nil }
        return root.itemController.modelSync(for: itemId)
    }
}

#Preview(traits: .mockData) {
    LinkRootView(isInspector: false)
}

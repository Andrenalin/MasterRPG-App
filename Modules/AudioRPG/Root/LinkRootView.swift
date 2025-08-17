// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct LinkRootView: View {
    let isInspector: Bool
    @Environment(AudioRootModel.self) private var root
    @Query(filter: #Predicate<AudioDataModel>{ $0.displayState == 0 }, sort: \AudioDataModel.name, animation: .smooth) private var items: [AudioDataModel]
    
    var body: some View {
        LinkItemListView(listController: root.listLinkController, parentModel: selectedModel, isInspector: isInspector) { itemId in
            if let model = root.itemController.modelSync(for: itemId) {
                MainRowView(model: model)
            }
        }
        .environment(DeviceRotationModel())
        .environment(CacheItemListModel())
        .onChange(of: items, initial: true) {
            root.listLinkController.update(items: items)
        }
    }
    
    var selectedModel: AudioDataModel? {
        guard let itemId = root.currentSelectedItemId else { return nil }
        return root.itemController.modelSync(for: itemId)
    }
}

#Preview(traits: .mockData) {
    LinkRootView(isInspector: false)
}

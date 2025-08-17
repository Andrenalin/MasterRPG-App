// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct LinkRootView: View {
    let isInspector: Bool
    @Environment(DiceRootModel.self) private var root
    @Query(filter: #Predicate<DiceDataModel>{ $0.displayState == 0 }, sort: \DiceDataModel.name, animation: .smooth) private var items: [DiceDataModel]
    
    var body: some View {
        LinkItemListView(listController: root.listLinkController, parentModel: selectedModel, isInspector: isInspector) { itemId in
            if let model = root.itemController.modelSync(for: itemId) {
                MainRowView(model: model)
            }
        }
        .environment(DeviceRotationModel())
        .environment(CacheItemListModel())
        .onChange(of: items) {
            root.listLinkController.update(items: items)
        }
    }
    
    var selectedModel: DiceDataModel? {
        guard let itemId = root.currentSelectedItemId else { return nil }
        return root.itemController.modelSync(for: itemId)
    }
}

#Preview(traits: .mockData) {
    LinkRootView(isInspector: false)
}

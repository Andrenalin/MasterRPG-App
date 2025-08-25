// @copyright André Trettin

import SwiftData
import SwiftUI

struct LinkRootView: View {
    let root: any ItemRootControllable
    let isInspector: Bool
    
    @Query(filter: #Predicate<ItemDataModel>{ $0.displayState == 0 }, sort: \ItemDataModel.name, animation: .smooth) private var items: [ItemDataModel]
    
    var body: some View {
        Text("")
//        LinkItemListView(listController: root.listLinkControllable, parentModel: selectedModel, isInspector: isInspector) { itemId in
//            if let model = root.itemControllable.modelSync(for: itemId) {
//                ItemRowView(root: root, model: model, cacheItemListModel: CacheItemListModel())
//                //MainRowView(model: model)
//            }
//        }
        .environment(DeviceRotationModel())
        .environment(CacheItemListModel())
        .onChange(of: items, initial: true) {
            withAnimation { root.listLinkControllable.update(items: items) }
        }
    }
    
    var selectedModel: ItemDataModel? {
        guard let itemId = root.currentSelectedItemId else { return nil }
        return root.itemControllable.modelSync(for: itemId)
    }
}

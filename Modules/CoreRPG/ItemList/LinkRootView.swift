// @copyright André Trettin

import SwiftData
import SwiftUI

public struct LinkRootView: View {
    public init(root: any ItemRootControllable, isInspector: Bool) {
        self.root = root
        self.isInspector = isInspector
        let predicate = #Predicate<ItemDataModel> { $0.displayState == 0 }
        let query = Query(filter: predicate, sort: \ItemDataModel.name, animation: .smooth)
        self._items = query
    }
    
    let root: any ItemRootControllable
    let isInspector: Bool
    
    @Query private var items: [ItemDataModel]
    
    public var body: some View {
        LinkItemListView(root: root, parentModel: nil, isInspector: isInspector)
            .environment(DeviceRotationModel())
            .environment(CacheItemListModel())
            .onChange(of: items, initial: true) {
                withAnimation { root.listLinkControllable.update(items: items.filter { $0.module == root.module }) }
            }
    }
    
    var selectedModel: ItemDataModel? {
        guard let itemId = root.currentSelectedItemId else { return nil }
        return root.itemControllable.modelSync(for: itemId)
    }
}

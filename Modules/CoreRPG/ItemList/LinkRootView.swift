// @copyright André Trettin

import SwiftData
import SwiftUI

public enum LinkRootType {
    case window
    case inspector
    case selection
}

public struct LinkRootView: View {
    public init(root: any ItemRootControllable, type: LinkRootType) {
        self.root = root
        self.type = type
        let predicate = #Predicate<ItemDataModel> { $0.displayState == 0 }
        let query = Query(filter: predicate, sort: \ItemDataModel.name, animation: .smooth)
        self._items = query
    }
    
    let root: any ItemRootControllable
    let type: LinkRootType
    
    @Query private var items: [ItemDataModel]
    
    public var body: some View {
        LinkItemListView(root: root, type: type, parentModel: nil)
            .environment(root.listDisplayModel)
            .environment(root.searchModel)        
            .environment(DeviceRotationModel())
            .environment(CacheItemListModel())
            .onChange(of: items, initial: true) {
                withAnimation { root.listLinkControllable.update(items: items.filter { $0.module == root.module }) }
            }
    }
}

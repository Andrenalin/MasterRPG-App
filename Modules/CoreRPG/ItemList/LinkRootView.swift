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
    }
    
    let root: any ItemRootControllable
    let type: LinkRootType
    
    public var body: some View {
        LinkItemListView(root: root, type: type, parentModel: nil)
            .environment(root.listDisplayModel)
            .environment(root.searchModel)        
            .environment(CacheItemListModel())
            .onChange(of: root.itemControllable.itemCacheModel.itemIds, initial: true) {
                withAnimation { root.listLinkControllable.update(items: root.itemControllable.allItems(), parentModel: nil) }
            }
    }
}

// @copyright André Trettin

import SwiftData
import SwiftUI

public enum LinkRootType {
    case window
    case inspector
    case selection
}

public struct LinkItemRootView: View {
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
            .environment(root.folderListControllable.cacheListItemModel)
            .onChange(of: root.itemControllable.itemDataModel.items, initial: true) {
                withAnimation { root.folderListControllable.update(items: root.itemControllable.itemDataModel.items.map { root.itemControllable.itemOrEmpty(for: $0) }, parentModel: nil) }
            }
    }
}

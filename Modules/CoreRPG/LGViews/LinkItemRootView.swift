// @copyright André Trettin

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
            .environment(root.folderLinkControllable.cacheListItemModel)
    }
}

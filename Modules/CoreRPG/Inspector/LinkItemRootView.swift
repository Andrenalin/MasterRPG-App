// @copyright André Trettin

import SwiftUI

public enum LinkRootType {
    case window
    case inspector
    case selection
    case selectionInline
}

public struct LinkItemRootView: View {
    public init(root: any ItemRootControllable, type: LinkRootType, itemSelectionModel: ItemSelectionModel) {
        self.root = root
        self.type = type
        self.itemSelectionModel = itemSelectionModel
    }
    
    let root: any ItemRootControllable
    let type: LinkRootType
    let itemSelectionModel: ItemSelectionModel
        
    public var body: some View {
        let _ = Self._printChanges()
        LinkItemListView(root: root, type: type, selectionModel: itemSelectionModel, parentModel: parentModel)
            .environment(root.folderLinkControllable.searchModel)
            .environment(root.folderLinkControllable.cacheListItemModel)
    }
    
    var parentModel: (any ItemDataAccessable)? {
        guard let parentId = itemSelectionModel.onlyChildrenFrom else { return nil }
        return root.itemControllable.itemSync(for: parentId)
    }
}

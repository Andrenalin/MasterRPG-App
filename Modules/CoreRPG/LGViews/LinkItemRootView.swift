// @copyright André Trettin

import SwiftUI

public enum LinkRootType {
    case window
    case inspector
    case selection
    case selectionInline
}

public struct LinkItemRootView: View {
    public init(root: any ItemRootControllable, type: LinkRootType) {
        self.root = root
        self.type = type
    }
    
    let root: any ItemRootControllable
    let type: LinkRootType
        
    @Environment(ItemSelectionModel.self) private var selectionModel
    
    public var body: some View {
        let _ = Self._printChanges()
        LinkItemListView(root: root, type: type, parentModel: parentModel)
            .environment(root.folderLinkControllable.searchModel)
            .environment(root.folderLinkControllable.cacheListItemModel)
    }
    
    var parentModel: (any ItemDataAccessable)? {
        guard let parentId = selectionModel.onlyChildrenFrom else { return nil }
        return root.itemControllable.itemSync(for: parentId)
    }
}

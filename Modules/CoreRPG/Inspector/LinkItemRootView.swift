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
        if let parentId = itemSelectionModel.onlyChildrenFrom {
            self._parentModel = State(initialValue: root.itemControllable.itemSync(for: parentId))
        } else {
            self._parentModel = State(initialValue: nil)
        }
    }
    
    let root: any ItemRootControllable
    let type: LinkRootType
    let itemSelectionModel: ItemSelectionModel
    
    @State private var parentModel: (any ItemDataAccessable)?
        
    public var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        
        LinkItemListView(root: root, type: type, selectionModel: itemSelectionModel, parentModel: parentModel)
            .task(id: itemSelectionModel.onlyChildrenFrom) {
                // Using task instead of onChange for better lifecycle management
                // and automatic cancellation when the ID changes
                if let newValue = itemSelectionModel.onlyChildrenFrom {
                    parentModel = root.itemControllable.itemSync(for: newValue)
                } else {
                    parentModel = nil
                }
            }
    }
}

#Preview {
    LinkItemRootView(
        root: ItemRootController.fake,
        type: .inspector,
        itemSelectionModel: ItemSelectionModel()
    )
}

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

    /// Derived directly from `itemSelectionModel.onlyChildrenFrom` on every body evaluation —
    /// not `@State`, since `itemSelectionModel` is `@Observable` and this view owns no state
    /// of its own here. A plain computed property tracks changes to `onlyChildrenFrom`
    /// automatically and avoids the one-frame gap an `@State` seeded from it in `init` (and
    /// only kept in sync afterward by a `.task(id:)`) would otherwise risk. `LinkItemListView`
    /// below only keys off `parentModel?.id`, so recomputing this on every re-render is safe.
    var parentModel: (any ItemDataAccessible)? {
        guard let parentId = itemSelectionModel.onlyChildrenFrom else { return nil }
        return root.itemControllable.itemSync(for: parentId)
    }

    public var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        LinkItemListView(root: root, type: type, selectionModel: itemSelectionModel, parentModel: parentModel)
    }
}

#Preview {
    LinkItemRootView(
        root: ItemRootController.fake,
        type: .inspector,
        itemSelectionModel: ItemSelectionModel()
    )
}

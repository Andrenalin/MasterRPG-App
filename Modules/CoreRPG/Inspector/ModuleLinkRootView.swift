// @copyright André Trettin

import SwiftUI

/// A module's link list: its root model from the environment, shown as the shared link list.
/// Each module names it with a typealias. See CODE_AUDIT_Audio2 §9.11.
public struct ModuleLinkRootView<Root: ItemRootControllable & Observable & AnyObject>: View {
    public init(type: LinkRootType, itemSelectionModel: ItemSelectionModel) {
        self.type = type
        self.itemSelectionModel = itemSelectionModel
    }

    let type: LinkRootType
    let itemSelectionModel: ItemSelectionModel

    @Environment(Root.self) private var root

    public var body: some View {
        LinkItemRootView(root: root.rootController, type: type, itemSelectionModel: itemSelectionModel)
    }
}

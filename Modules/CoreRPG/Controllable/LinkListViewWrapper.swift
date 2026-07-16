// @copyright André Trettin

import SwiftUI

/// Optimized wrapper for link list views - eliminates AnyView overhead.
public struct LinkListViewWrapper<Controller: ViewControllable>: View {
    let controller: Controller
    let rootController: ItemRootController
    let type: LinkRootType
    let itemSelectionModel: ItemSelectionModel

    public init(controller: Controller, rootController: ItemRootController, type: LinkRootType, itemSelectionModel: ItemSelectionModel) {
        self.controller = controller
        self.rootController = rootController
        self.type = type
        self.itemSelectionModel = itemSelectionModel
    }

    public var body: some View {
        controller.linkListView(rootController: rootController, type: type, itemSelectionModel: itemSelectionModel)
    }
}

#Preview("Link List Wrapper") {
    LinkListViewWrapper(
        controller: FakeViewController(),
        rootController: ItemRootController.fake,
        type: .inspector,
        itemSelectionModel: ItemSelectionModel()
    )
}

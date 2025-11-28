// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import SwiftUI

struct RootExtendedDetail: View {
    let itemRowTreeModel: ItemRowTreeModel
    let tabId: UUID
    
    @Environment(SpaceRootModel.self) private var root
    
    var body: some View {
        RootDetail(editController: root.editController)
            .environment(root.listController(tabId: tabId).model)
    }
}

struct RootDetail: View {
    let editController: EditController
    
    @Environment(SpaceRootModel.self) private var root
    @Environment(\.navigator) private var navigator
    @Environment(ListModel.self) private var listModel
    
    var body: some View {
        DetailRootView(root: root, editController: editController, model: editController.model, isSubFolder: false)
            .onChange(of: listController.model.selectedItem) {
                if listController.model.selectedItem == nil {
                    navigator.back()
                }
            }
    }
    
    private var listController: ListController {
        root.listController(model: listModel)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(SpaceRootModel.self) var root
    RootExtendedDetail(itemRowTreeModel: ItemRowTreeModel(itemId: root.itemController.itemDataModel.items.first!, typeId: .space), tabId: KnownRoutes.mainTabId)
        .environment(\.locale, .init(identifier: "de"))
}

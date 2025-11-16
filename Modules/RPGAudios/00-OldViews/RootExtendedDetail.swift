// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import SwiftUI

struct RootExtendedDetail: View {
    let itemRowTreeModel: ItemRowTreeModel
    let tabId: UUID
    
    @Environment(AudioRootModel.self) private var root
    
    var body: some View {
        let _ = Self._printChanges()
        
        RootDetail(editController: root.editController(for: itemRowTreeModel, type: .main))
            .environment(root.listController(tabId: tabId).model)
    }
}

struct RootDetail: View {
    let editController: EditController
    
    @Environment(AudioRootModel.self) private var root
    @Environment(\.navigator) private var navigator
    @Environment(ListModel.self) private var listModel
        
    var body: some View {
        let _ = Self._printChanges()
        
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

// @copyright André Trettin


import CoreRPG
import SwiftUI

struct RootExtendedDetail: View {
    let itemRowTreeModel: ItemRowTreeModel
    let tabId: UUID
    
    @Environment(PdfRootModel.self) private var root
    
    var body: some View {
        RootDetail(editController: root.editController)
            .environment(root.listController(tabId: tabId).model)
    }
}

struct RootDetail: View {
    let editController: EditController
    
    @Environment(PdfRootModel.self) private var root
    @Environment(\.navigator) private var navigator
    @Environment(ListModel.self) private var listModel
    
    var body: some View {
        DetailRootView(root: root, model: editController.model)
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

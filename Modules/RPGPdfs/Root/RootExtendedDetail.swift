// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct RootExtendedDetail: View {
    let itemRowTreeModel: ItemRowTreeModel
    let tabId: UUID
    
    @Environment(PdfRoot.self) private var root
    
    var body: some View {
        RootDetail(editController: root.editController(for: itemRowTreeModel, type: .main))
            .environment(root.listController(tabId: tabId).model)
    }
}

struct RootDetail: View {
    let editController: EditController
    
    @Environment(PdfRoot.self) private var root
    @Environment(\.navigator) private var navigator
    @Environment(ListModel.self) private var listModel
    
    var body: some View {
        PdfDetailEditor(editController: editController, model: editController.model)
            .onChange(of: listController.model.selectedItem) {
                if listController.model.selectedItem == nil {
                    navigator.send(PdfRoute.detail(nil, UUID()))
                }
            }
    }
    
    private var listController: ListController {
        root.listController(model: listModel)
    }
}

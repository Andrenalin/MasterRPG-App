// @copyright André Trettin

import CoreRPG
import SwiftUI

struct RootExtendedDetail: View {
    let itemRowTreeModel: ItemRowTreeModel
    let tabId: UUID
    
    @Environment(TableRootModel.self) private var root
    
    var body: some View {
        RootDetail(editController: root.editController)
            .environment(root.listController(tabId: tabId).model)
    }
}

struct RootDetail: View {
    let editController: EditController
    
    @Environment(TableRootModel.self) private var root
    @Environment(\.navigator) private var navigator
    @Environment(ListModel.self) private var listModel
    
    var body: some View {
        TableDetailEditor(editController: editController, model: editController.model)
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

struct RootEditDetail: View {
    let itemId: UUID
    
    @Environment(TableRootModel.self) private var root
    @Environment(\.navigator) private var navigator
    
    @State private var loaded: Bool = false
    @State private var tabId = UUID()
    
    var editController: EditController {
        root.editController
    }

    private var listController: ListController {
        let controller = root.listController(tabId: tabId)
        if !loaded {
            controller.model.selectedItems = [ItemRowTreeModel(itemId: itemId, typeId: .table)]
            controller.model.selectedItem = ItemRowTreeModel(itemId: itemId, typeId: .table)
        }
        return controller
    }

    var body: some View {
        RootEditDetailIm(listController: listController, editController: editController)
            .onAppear {
                loaded = true
            }
    }
}

struct RootEditDetailIm: View {
    let listController: ListController
    let editController: EditController
    
    @Environment(TableRootModel.self) private var root
    @Environment(\.navigator) private var navigator
    
    var body: some View {
        TableDetailEditor(editController: editController, model: editController.model)
            .environment(listController.model)
            .environment(\.itemSplitViewSizeMode, .small)
            .onChange(of: listController.model.selectedItem) {
                navigator.pop()
            }
    }
}

// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import RPGPhotos
import RPGTables

struct RootExtendedDetail: View {
    let itemRowTreeModel: ItemRowTreeModel
    let tabId: UUID
    
    @Environment(ValueRoot.self) private var root
    
    var body: some View {
        let _ = Self._printChanges()
        RootDetail(editController: root.editController(for: itemRowTreeModel, type: .main))
            .environment(root.listController(tabId: tabId).model)
    }
}

struct RootDetail: View {
    let editController: EditController
    
    @Environment(ValueRoot.self) private var root
    @Environment(\.navigator) private var navigator
    @Environment(ListModel.self) private var listModel
    
    var body: some View {
        let _ = Self._printChanges()
        let _ = print(Unmanaged.passUnretained(editController.model).toOpaque())

        detailView(selectedItem: listController.model.selectedItem ?? .empty)
            .onChange(of: listController.model.selectedItem) {
                if listController.model.selectedItem == nil {
                    navigator.send(ValueRoute.detail(nil, UUID()))
                }
            }
    }
    
    private var listController: ListController {
        root.listController(model: listModel)
    }
    
    @ViewBuilder
    private func detailView(selectedItem: ItemRowTreeModel) -> some View {
        switch selectedItem.model.typeId {
        case .photo:
            root.photoRoot.viewController.detailEditor(for: selectedItem, module: root.itemController.itemDataModel.networkModule)
        case .table:
            root.tableRoot.viewController.detailEditor(for: selectedItem, module: root.itemController.itemDataModel.networkModule)
        default:
            ValueDetailEditor(editController: editController, model: editController.model)
        }
    }
}

struct RootEditDetail: View {
    let itemId: UUID
    
    @Environment(ValueRoot.self) private var root
    @Environment(\.navigator) private var navigator
    
    @State private var loaded: Bool = false
    @State private var tabId = UUID()
    
    var editController: EditController {
        root.editController(for: ItemRowTreeModel(itemId: itemId, typeId: .value), type: .module(.value))
    }

    private var listController: ListController {
        let controller = root.listController(tabId: tabId)
        if !loaded {
            controller.model.selectedItems = [ItemRowTreeModel(itemId: itemId, typeId: .value)]
            controller.model.selectedItem = ItemRowTreeModel(itemId: itemId, typeId: .value)
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
    
    @Environment(ValueRoot.self) private var root
    @Environment(\.navigator) private var navigator
    
    var body: some View {
        let _ = Self._printChanges()
        ValueDetailEditor(editController: editController, model: editController.model)
            .environment(listController.model)
            .environment(\.itemSplitViewSizeMode, .small)
            .onChange(of: listController.model.selectedItem) {
                navigator.pop()
            }
    }
}

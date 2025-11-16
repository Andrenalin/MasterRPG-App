// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import SwiftUI
import RPGAudios
import RPGWeathers
import RPGValues
import RPGTables
import RPGSpaces
import RPGPhotos
import RPGPdfs
import RPGMaps

struct RootExtendedDetail: View {
    let itemRowTreeModel: ItemRowTreeModel
    let tabId: UUID
    
    @Environment(AdventureRootModel.self) private var root
    
    var body: some View {
        let _ = Self._printChanges()
        let _ = print(root.listController(tabId: tabId).model.listTitleName)
        
        RootDetail(editController: root.editController(for: itemRowTreeModel, type: .main))
            .environment(root.listController(tabId: tabId).model)
    }
}

struct RootDetail: View {
    let editController: EditController
    
    @Environment(AdventureRootModel.self) private var root
    @Environment(\.navigator) private var navigator
    @Environment(ListModel.self) private var listModel
    
    var body: some View {
        let _ = Self._printChanges()
        let _ = print(listModel.listTitleName)

        detailView(selectedItem: listController.model.selectedItem ?? .empty)
            .onChange(of: listController.model.selectedItem) {
                if listController.model.selectedItem == nil {
                    navigator.back()
                }
            }
    }
    
    private var listController: ListController {
        root.listController(model: listModel)
    }
    
    @ViewBuilder
    private func detailView(selectedItem: ItemRowTreeModel) -> some View {
        switch selectedItem.model.typeId {
        case .audio:
            root.audioRoot.viewController.detailEditor(root: root.audioRoot, for: selectedItem, module: root.itemController.itemDataModel.networkModule)
        case .map:
            root.mapRoot.viewController.detailEditor(for: selectedItem, module: root.itemController.itemDataModel.networkModule)
        case .pdf:
            root.pdfRoot.viewController.detailEditor(root: root.pdfRoot, for: selectedItem, module: root.itemController.itemDataModel.networkModule)
        case .photo:
            root.photoRoot.viewController.detailEditor(root: root.photoRoot, for: selectedItem, module: root.itemController.itemDataModel.networkModule)
        case .space:
            root.spaceRoot.viewController.detailEditor(root: root.spaceRoot, for: selectedItem, module: root.itemController.itemDataModel.networkModule)
        case .table:
            root.tableRoot.viewController.detailEditor(for: selectedItem, module: root.itemController.itemDataModel.networkModule)
        case .value:
            root.valueRoot.viewController.detailEditor(for: selectedItem, module: root.itemController.itemDataModel.networkModule)
        case .weather:
            root.weatherRoot.viewController.detailEditor(root: root.weatherRoot, for: selectedItem, module: root.itemController.itemDataModel.networkModule)
        default:
            AdventureDetailEditor(editController: editController, model: editController.model)
        }
    }
}

struct RootEditDetail: View {
    let itemId: UUID
    
    @Environment(AdventureRootModel.self) private var root
    @Environment(\.navigator) private var navigator
    
    @State private var loaded: Bool = false
    @State private var tabId = UUID()
    
    var editController: EditController {
        root.editController(for: ItemRowTreeModel(itemId: itemId, typeId: .adventure), type: .module(.adventure))
    }

    private var listController: ListController {
        let controller = root.listController(tabId: tabId)
        if !loaded {
            controller.model.selectedItems = [ItemRowTreeModel(itemId: itemId, typeId: .adventure)]
            controller.model.selectedItem = ItemRowTreeModel(itemId: itemId, typeId: .adventure)
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
    
    @Environment(AdventureRootModel.self) private var root
    @Environment(\.navigator) private var navigator
    
    var body: some View {
        AdventureDetailEditor(editController: editController, model: editController.model)
            .environment(listController.model)
            .environment(\.itemSplitViewSizeMode, .small)
            .onChange(of: listController.model.selectedItem) {
                navigator.pop()
            }
    }
}

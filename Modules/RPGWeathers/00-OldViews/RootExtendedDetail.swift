// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import SwiftUI
import RPGPhotos

struct RootExtendedDetail: View {
    let itemRowTreeModel: ItemRowTreeModel
    let tabId: UUID
    
    @Environment(WeatherRootModel.self) private var root
    
    var body: some View {
        RootDetail(editController: root.editController)
            .environment(root.listController(tabId: tabId).model)
    }
}

struct RootDetail: View {
    let editController: EditController
    
    @Environment(WeatherRootModel.self) private var root
    @Environment(\.navigator) private var navigator
    @Environment(ListModel.self) private var listModel
    
    var body: some View {
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
        case .photo:
            root.photoRoot.viewController.detailEditor(root: root.photoRoot, for: selectedItem, module: root.itemController.itemDataModel.networkModule)
        default:
            DetailRootView(root: root, editController: editController, model: editController.model, isSubFolder: false)
        }
    }
}

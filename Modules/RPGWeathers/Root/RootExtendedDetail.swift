// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct RootExtendedDetail: View {
    let itemRowTreeModel: ItemRowTreeModel
    let tabId: UUID
    
    @Environment(WeatherRoot.self) private var root
    
    var body: some View {
        RootDetail(editController: root.editController(for: itemRowTreeModel, type: .main))
            .environment(root.listController(tabId: tabId).model)
    }
}

struct RootDetail: View {
    let editController: EditController
    
    @Environment(WeatherRoot.self) private var root
    @Environment(\.navigator) private var navigator
    @Environment(ListModel.self) private var listModel
    
    var body: some View {
        detailView(selectedItem: listController.model.selectedItem ?? .empty)
            .onChange(of: listController.model.selectedItem) {
                if listController.model.selectedItem == nil {
                    navigator.send(WeatherRoute.detail(nil, UUID()))
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
        default:
            WeatherDetailEditor(editController: editController, model: editController.model)
        }
    }
}

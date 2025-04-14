// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct RootLinkWindow: View {
    let editController: EditController
    let tabId: UUID
    let selection: Bool
    
    @Environment(PhotoRoot.self) private var root
    @Environment(\.navigator) private var navigator
    @State private var firstInit: Bool = true
    
    var body: some View {
        NavigationStack {
            LinkItemList(listController: listController) { item, isSelected in
                PhotoRow(item: item, isSelected: isSelected, cacheItemListModel: editController.cacheItemListModel)
            }
            .focusedSceneValue(\.selectedModule, .constant(root.itemController.itemDataModel.networkModule))
        }
        .environment(listController.model)
        .onChange(of: root.itemController.itemDataModel.items, initial: true) {
            if firstInit {
                listController.update(models: root.itemController.itemDataModel.items.map { ItemRowModel(itemId: $0, typeId: root.itemController.itemDataModel.networkModule) })
                firstInit = false
            } else {
                withAnimation {
                    listController.update(models: root.itemController.itemDataModel.items.map { ItemRowModel(itemId: $0, typeId: root.itemController.itemDataModel.networkModule) })
                }
            }
        }
        .onChange(of: root.itemController.itemDataModel.updateHiddenCounter) {
            withAnimation { listController.resetFilter() }
        }
        .onChange(of: root.rootModel.selectedItem, initial: true) {
            guard selection == true, let selectedItem = root.rootModel.selectedItem else { return }
            root.rootModel.selectedItem = nil
            withAnimation { listController.setSelectedItem(model: selectedItem) }
        }
        .onChange(of: root.rootModel.gameItemSelection, initial: true) {
            guard let selectedItem = root.rootModel.gameItemSelection else { return }
            root.rootModel.gameItemSelection = nil
            withAnimation { listController.setSelectedItem(model: selectedItem) }
        }
        .onChange(of: listController.model.selectedItem, initial: false) {
            navigator.send(PhotoRoute.detail(listController.model.selectedItem, tabId))
        }
        .onChange(of: listController.model.searchText, initial: false) {
            editController.resetSearch(listController.model.searchText)
        }
    }
    
    private var listController: ListController {
        root.listController(tabId: tabId)
    }
}

#Preview {
    RootLinkWindow(editController: .preview, tabId: UUID(), selection: false)
        .environment(\.locale, Locale(identifier: "de"))
        .environment(PhotoRoot.previewWithData)
}

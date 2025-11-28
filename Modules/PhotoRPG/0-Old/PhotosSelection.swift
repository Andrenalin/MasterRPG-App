// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import SwiftUI

struct PhotoSelection: View {
    init(editController: any EditControllable, selectionModel: SelectionModel, inline: Bool) {
        self.editController = editController
        self.selectionModel = selectionModel
        self.inline = inline
    }
    
    let editController: any EditControllable
    let selectionModel: SelectionModel
    let inline: Bool
        
    @Environment(PhotoRootModel.self) private var root
    
    var body: some View {
        let _ = Self._printChanges()
        ItemSelectionNaviEditor(editController: editController, selectionModel: selectionModel, title: "Photo", bundle: .module, value: .photo, inline: inline, selectorRoute: SelectionRoute.selection(selectionModel)) { photoId in
            root.viewController.rowView(root: root, item: ItemRowTreeModel(itemId: photoId, typeId: root.itemController.itemDataModel.networkModule), isSelected: false, cacheItemListModel: editController.cacheItemListModel)
        }
    }
}

struct PhotosSelection<Action: View>: View {
    let editController: any EditControllable
    let model: Binding<[UUID]>
    let selected: Binding<UUID?>?
    let filter: ItemListCategory
    let selection: () -> [ItemRowModel]
    let toggleSelection: (ItemRowModel, Bool) -> Void
    let actionView: () -> Action
    
    @Environment(PhotoRootModel.self) private var root
    @Environment(SelectionSheetLinkModel.self) private var selectionSheetLinkModel
    
    var body: some View {
        ItemsSelectionEditor(editController: editController, model: model, selected: selected, title: "Photos", bundle: .module, value: .photo) { photoId in
            root.viewController.rowView(root: root, item: ItemRowTreeModel(itemId: photoId, typeId: root.itemController.itemDataModel.networkModule), isSelected: false, cacheItemListModel: editController.cacheItemListModel)
        } selectorView: {
            root.viewController.viewSelect(root: root, filter: filter, selection: selection, toggleSelection: toggleSelection) { selectionSheetLinkModel.selection = false }
        } actionView: {
            actionView()
        } valueFactory: { id in
            id
        }
    }
}

enum SelectionRoute: Hashable {
    case selection(SelectionModel)
}

extension SelectionRoute: NavigationDestination {
    var body: some View {
        let _ = Self._printChanges()
        switch self {
        case .selection(let model):
            SelectionRouteView(selectionModel: model)
        }
    }
}

struct SelectionRouteView: View {
    let selectionModel: SelectionModel
    
    @Environment(PhotoRootModel.self) private var root
    
    var body: some View {
        let _ = Self._printChanges()
        SelectionRouteInitView(root: root, selectionModel: selectionModel)
    }
}

struct SelectionRouteInitView: View {
    init(root: PhotoRootModel, selectionModel: SelectionModel) {
        self.root = root
        self.selectionModel = selectionModel
        
        let listController = root.listController(tabId: ViewController.selectionTabId)
        if listController.model.selectionMode?.selectionId != selectionModel.id {
            let selectionMode = SelectionMode(selectionId: selectionModel.id) {
                if let selectedItemId = selectionModel.selectedValue {
                    return [ItemRowModel(itemId: selectedItemId, typeId: .photo)]
                } else {
                    return []
                }
            } toggle: { row, isSelected in
                if row.itemId == selectionModel.selectedValue {
                    selectionModel.selectedValue = nil
                } else {
                    selectionModel.selectedValue = row.itemId
                }
            }
            listController.setSelection(onlyItems: false, onlyEntries: false, filter: selectionModel.filter, isHidden: true, focus: nil, mode: selectionMode)
        }
    }
    
    let root: PhotoRootModel
    let selectionModel: SelectionModel
    
    @Environment(\.navigator) private var navigator
    
    var body: some View {
        let _ = Self._printChanges()

        RootNaviList(root: root, tabId: ViewController.selectionTabId)
            .itemSplitViewSizeMode(.small)
            .itemListChildrenConfiguration(canNavigate: false)
            .itemListConfiguration(modalOk: true) {
                selectionModel.currentValue <=> selectionModel.selectedValue
                navigator.dismiss()
            }
    }
}

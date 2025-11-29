// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftUI

struct PdfSelectionView: View {
    init(root: PdfRootModel, selectionModel: SelectionModel) {
        self.root = root
        self.selectionModel = selectionModel
        
        let listController = root.listController(tabId: ViewController.selectionTabId)
        if listController.model.selectionMode?.selectionId != selectionModel.id {
            let selectionMode = SelectionMode(selectionId: selectionModel.id) {
                if let selectedItemId = selectionModel.selectedValue {
                    return [ItemRowModel(itemId: selectedItemId, typeId: .pdf)]
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
    
    let root: PdfRootModel
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

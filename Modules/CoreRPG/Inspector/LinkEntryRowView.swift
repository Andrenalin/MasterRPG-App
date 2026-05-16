// @copyright André Trettin

import Foundation
import SwiftUI

struct LinkEntryRowView: View {
    let root: any ItemRootControllable
    let item: ListItemModel
    let listDisplayModel: ListDisplayModel

    var editController: (any EntryDataEditable)? {
        root.editControllable as? (any EntryDataEditable)
    }
    var body: some View {
        if let editController {
            EntryEditRow(root: root, editController: editController, itemId: item.model.id, entry: item.model[entryId], cacheItemListModel: root.folderLinkControllable.cacheListItemModel, listDisplayModel: listDisplayModel, searchModel: root.folderLinkControllable.searchModel)
        } else {
            Text("\(item.model[entryId].name): \(item.model[entryId].content)")
        }
    }
    
    var entryId: UUID {
        item.entryId ?? UUID()
    }
}

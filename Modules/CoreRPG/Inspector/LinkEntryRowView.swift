// @copyright André Trettin

import Foundation
import SwiftUI

struct LinkEntryRowView: View {
    let root: any ItemRootControllable
    let item: FolderListItemModel
    let listDisplayModel: ListDisplayModel

    var editController: (any EntryDataEditable)? {
        root.editControllable as? (any EntryDataEditable)
    }

    var body: some View {
        if let entryId = item.source.entryId,
           let itemModel = root.itemControllable.itemSync(for: item.source.itemId) {
            if let editController {
                EntryEditRow(root: root, editController: editController, itemId: item.source.itemId, entry: itemModel[entryId], cacheItemListModel: root.folderLinkControllable.cacheListItemModel, listDisplayModel: listDisplayModel, searchModel: root.folderLinkControllable.searchModel)
            } else {
                Text("\(itemModel[entryId].name): \(itemModel[entryId].content)")
            }
        }
    }
}

#Preview {
    LinkEntryRowView(
        root: ItemRootController.fake,
        item: FolderListItemModel(
            id: UUID(),
            source: ItemRowModel(itemId: UUID(), entryId: UUID(), typeId: .none),
            destination: nil,
            level: 0,
            isShown: true
        ),
        listDisplayModel: ListDisplayModel()
    )
}

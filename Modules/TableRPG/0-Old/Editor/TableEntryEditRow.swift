// @copyright André Trettin

import CoreRPG
import SwiftUI

struct TableEntryEditRow: View {
    let editController: EditController
    let entrySectionEditorModel: EntrySectionEditorModel<TableModel>

    @Environment(TableRootModel.self) private var root
    @Environment(EntrySectionSelectionModel.self) private var entrySectionSelectionModel

    var body: some View {
        EntryRow(model: editController.model, item: ItemRowTreeModel(itemId: editController.model.id, entryId: entryId, typeId: root.itemController.itemDataModel.networkModule), isEditing: true, cacheItemListModel: editController.editorModel.cacheItemListModel)
    }

    private var entryId: UUID {
        entrySectionSelectionModel.id
    }
}

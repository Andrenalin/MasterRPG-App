// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct ValueEntryEditRow: View {
    let editController: EditController
    let entrySectionEditorModel: EntrySectionEditorModel<ValueModel>

    @Environment(ValueRoot.self) private var root
    @Environment(EntrySectionSelectionModel.self) private var entrySectionSelectionModel

    var body: some View {
        EntryRow(linkController: root.linkController, model: editController.model, item: ItemRowTreeModel(id: UUID(), model: ItemRowModel(itemId: editController.model.id, entryId: entryId, typeId: root.itemController.itemDataModel.networkModule)), isEditing: true, hasQuickEditor: false, cacheItemListModel: editController.cacheItemListModel)
    }

    private var entryId: UUID {
        entrySectionSelectionModel.id
    }
}

// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct AdventureEntryEditRow: View {
    let editController: EditController
    let entrySectionEditorModel: EntrySectionEditorModel<AdventureModel>

    @Environment(AdventureRoot.self) private var root
    @Environment(EntrySectionSelectionModel.self) private var entrySectionSelectionModel

    var body: some View {
        EntryRow(model: editController.model, item: ItemRowTreeModel(id: UUID(), model: ItemRowModel(itemId: editController.model.id, entryId: entryId, typeId: .adventure)), isEditing: true, cacheItemListModel: editController.cacheItemListModel)
    }

    private var entryId: UUID {
        entrySectionSelectionModel.id
    }
}

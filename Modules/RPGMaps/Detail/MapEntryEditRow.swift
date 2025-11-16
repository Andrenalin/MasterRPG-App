// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct MapEntryEditRow: View {
    let editController: EditController
    let entrySectionEditorModel: EntrySectionEditorModel<MapModel>

    @Environment(MapRootModel.self) private var root
    @Environment(EntrySectionSelectionModel.self) private var entrySectionSelectionModel

    var body: some View {
        EntryRow(model: editController.model, item: ItemRowTreeModel(id: UUID(), model: ItemRowModel(itemId: editController.model.id, entryId: entryId, typeId: .map)), isEditing: true, cacheItemListModel: editController.cacheItemListModel)
    }

    private var entryId: UUID {
        entrySectionSelectionModel.id
    }
}

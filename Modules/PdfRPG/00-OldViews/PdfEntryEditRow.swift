// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct PdfEntryEditRow: View {
    let editController: EditController
    let entrySectionEditorModel: EntrySectionEditorModel<PdfModel>

    @Environment(PdfRootModel.self) private var root
    @Environment(EntrySectionSelectionModel.self) private var entrySectionSelectionModel

    var body: some View {
        EntryRow(item: ItemRowTreeModel(itemId: editController.model.id, entryId: entryId, typeId: root.itemController.itemDataModel.networkModule), isSelected: false, cacheItemListModel: editController.cacheItemListModel)
    }

    private var entryId: UUID {
        entrySectionSelectionModel.id
    }
}

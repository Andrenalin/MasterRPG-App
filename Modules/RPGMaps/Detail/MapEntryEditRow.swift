//
//  TableEntryEditRow.swift
//  MasterRPG
//
//  Created by Andre Trettin on 18/6/2568 BE.
//


// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct TableEntryEditRow: View {
    let editController: EditController
    let entrySectionEditorModel: EntrySectionEditorModel<TableModel>

    @Environment(TableRoot.self) private var root
    @Environment(EntrySectionSelectionModel.self) private var entrySectionSelectionModel

    var body: some View {
        EntryRow(model: editController.model, item: ItemRowTreeModel(itemId: editController.model.id, entryId: entryId, typeId: root.itemController.itemDataModel.networkModule), isEditing: true, cacheItemListModel: editController.editorModel.cacheItemListModel)
    }

    private var entryId: UUID {
        entrySectionSelectionModel.id
    }
}

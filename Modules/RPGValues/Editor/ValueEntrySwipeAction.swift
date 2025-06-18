// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct ValueEntrySwipeAction: View {
    let editController: EditController
    let entrySectionEditorModel: EntrySectionEditorModel<ValueModel>
    let entryId: UUID
    let keyPath: WritableKeyPath<ValueModel, String>?

    var body: some View {
        @Bindable var entryModel = entrySectionEditorModel
        LinkSelectionButton(entryId: entryId, type: .dice, keyPath: keyPath, title: "Dice", bundle: .module, showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .pdf, keyPath: keyPath, title: "Pdf", bundle: .module,showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .table, keyPath: keyPath, title: "Table", bundle: .module,showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .value, keyPath: keyPath, title: "Value", bundle: .module,showLink: $entryModel.showLink)
    }
}

struct ValueEntrySwipeActionName: View {
    let editController: EditController
    let entrySectionEditorModel: EntrySectionEditorModel<ValueModel>

    @Environment(EntrySectionSelectionModel.self) private var entrySectionSelectionModel

    var body: some View {
        ValueEntrySwipeAction(editController: editController, entrySectionEditorModel: entrySectionEditorModel, entryId: entryId, keyPath: keyPath)
    }

    private var entryId: UUID {
        entrySectionSelectionModel.id
    }

    private var keyPath: WritableKeyPath<ValueModel, String>? {
        \.[entryId].name
    }
}

struct ValueEntrySwipeActionValue: View {
    let editController: EditController
    let entrySectionEditorModel: EntrySectionEditorModel<ValueModel>

    @Environment(EntrySectionSelectionModel.self) private var entrySectionSelectionModel

    var body: some View {
        ValueEntrySwipeAction(editController: editController, entrySectionEditorModel: entrySectionEditorModel, entryId: entryId, keyPath: keyPath)
    }

    private var entryId: UUID {
        entrySectionSelectionModel.id
    }

    private var keyPath: WritableKeyPath<ValueModel, String>? {
        \.[entryId].value
    }
}

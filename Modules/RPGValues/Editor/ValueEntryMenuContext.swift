// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct ValueEntryMenuContext: View {
    enum MenuType {
        case all
        case name
        case value
    }

    let editController: EditController
    let entrySectionEditorModel: EntrySectionEditorModel<ValueModel>
    let menuType: MenuType

    @Environment(EntrySectionSelectionModel.self) private var entrySectionSelectionModel

    var body: some View {
        @Bindable var entryModel = entrySectionEditorModel

        LinkSelectionButton(entryId: entryId, type: .dice, keyPath: keyPath, title: "Add Dice", bundle: .module, showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .pdf, keyPath: keyPath, title: "Add Pdf", bundle: .module, showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .table, keyPath: keyPath, title: "Add Table", bundle: .module, showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .value, keyPath: keyPath, title: "Add Value", bundle: .module, showLink: $entryModel.showLink)

        if !entrySectionEditorModel.selectedEntries.isEmpty {
            Button {
                let rootModel = entrySectionEditorModel.selectedEntries.first.map { ItemRowModel(itemId: editController.model.id, entryId: $0, typeId: .value) }
                guard let rootModel else { return }
                Task {
                    await editController.toggleGroup(for: rootModel, models: entrySectionEditorModel.selectedEntries.dropFirst().map { ItemRowModel(itemId: editController.model.id, entryId: $0, typeId: .value) })
                }
            } label: {
                Label(editController.groupTitle(for: entrySectionEditorModel.selectedEntries.dropFirst().map { ItemRowModel(itemId: editController.model.id, entryId: $0, typeId: .value)}, rootModel: entrySectionEditorModel.selectedEntries.first.map { ItemRowModel(itemId: editController.model.id, entryId: $0, typeId: .value)}), systemImage: "square.on.square.squareshape.controlhandles")
            }
        }
    }

    private var entryId: UUID {
        entrySectionSelectionModel.id
    }

    private var keyPath: WritableKeyPath<ValueModel, String>? {
        switch menuType {
            case .all: nil
            case .name: \.[entryId].name
            case .value: \.[entryId].value
        }
    }
}

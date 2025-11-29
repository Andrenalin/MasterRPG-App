// @copyright André Trettin

import CoreRPG
import SwiftUI

struct TableEntryMenuContext: View {
    enum MenuType {
        case all
        case name
        case content
    }

    let editController: EditController
    let entrySectionEditorModel: EntrySectionEditorModel<TableModel>
    let menuType: MenuType

    @Environment(EntrySectionSelectionModel.self) private var entrySectionSelectionModel

    var body: some View {
        @Bindable var entryModel = entrySectionEditorModel

        LinkSelectionButton(entryId: entryId, type: .dice, keyPath: keyPath, title: "Add Dice", bundle: .module, showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .table, keyPath: keyPath, title: "Add Table", bundle: .module, showLink: $entryModel.showLink)
    }

    private var entryId: UUID {
        entrySectionSelectionModel.id
    }

    private var keyPath: WritableKeyPath<TableModel, String>? {
        switch menuType {
            case .all: nil
            case .name: \.[entryId].name
            case .content: \.[entryId].content
        }
    }
}

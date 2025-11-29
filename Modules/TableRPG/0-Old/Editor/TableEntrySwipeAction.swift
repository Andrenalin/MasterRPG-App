// @copyright André Trettin

import CoreRPG
import SwiftUI

struct TableEntrySwipeAction: View {
    enum ActionType {
        case name
        case content
    }

    let editController: EditController
    let entrySectionEditorModel: EntrySectionEditorModel<TableModel>
    let actionType: ActionType

    @Environment(EntrySectionSelectionModel.self) private var entrySectionSelectionModel

    var body: some View {
        @Bindable var entryModel = entrySectionEditorModel
        LinkSelectionButton(entryId: entryId, type: .dice, keyPath: keyPath, title: "Dice", bundle: .module, showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .table, keyPath: keyPath, title: "Table", bundle: .module, showLink: $entryModel.showLink)
    }

    private var entryId: UUID {
        entrySectionSelectionModel.id
    }

    private var keyPath: WritableKeyPath<TableModel, String> {
        switch actionType {
            case .name: \.[entryId].name
            case .content: \.[entryId].content
        }
    }
}

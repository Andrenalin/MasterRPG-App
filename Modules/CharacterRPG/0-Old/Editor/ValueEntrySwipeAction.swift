// @copyright André Trettin

import CoreRPG
import SwiftUI

struct ValueEntrySwipeAction: View {
    enum ActionType {
        case name
        case value
    }

    let editController: EditController
    let entrySectionEditorModel: EntrySectionEditorModel<ValueModel>
    let actionType: ActionType

    @Environment(EntrySectionSelectionModel.self) private var entrySectionSelectionModel

    var body: some View {
        @Bindable var entryModel = entrySectionEditorModel
        LinkSelectionButton(entryId: entryId, type: .dice, keyPath: keyPath, title: "Dice", bundle: .module, showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .pdf, keyPath: keyPath, title: "Pdf", bundle: .module,showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .table, keyPath: keyPath, title: "Table", bundle: .module,showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .value, keyPath: keyPath, title: "Value", bundle: .module,showLink: $entryModel.showLink)
    }

    private var entryId: UUID {
        entrySectionSelectionModel.id
    }

    private var keyPath: WritableKeyPath<ValueModel, String> {
        switch actionType {
            case .name: \.[entryId].name
            case .value: \.[entryId].value
        }
    }
}

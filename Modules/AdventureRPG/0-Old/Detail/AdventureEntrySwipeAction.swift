// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct AdventureEntrySwipeAction: View {
    enum ActionType {
        case name
        case content
    }

    let editController: EditController
    let entrySectionEditorModel: EntrySectionEditorModel<AdventureModel>
    let actionType: ActionType

    @Environment(EntrySectionSelectionModel.self) private var entrySectionSelectionModel

    var body: some View {
        @Bindable var entryModel = entrySectionEditorModel
        LinkSelectionButton(entryId: entryId, type: .adventure, keyPath: keyPath, title: "Adventure", bundle: .module, showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .audio, keyPath: keyPath, title: "Audio", bundle: .module, showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .dice, keyPath: keyPath, title: "Dice", bundle: .module, showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .map, keyPath: keyPath, title: "Map", bundle: .module, showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .pdf, keyPath: keyPath, title: "Pdf", bundle: .module, showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .photo, keyPath: keyPath, title: "Photo", bundle: .module, showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .space, keyPath: keyPath, title: "Space", bundle: .module, showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .table, keyPath: keyPath, title: "Table", bundle: .module, showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .value, keyPath: keyPath, title: "Value", bundle: .module, showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .weather, keyPath: keyPath, title: "Weather", bundle: .module, showLink: $entryModel.showLink)    }

    private var entryId: UUID {
        entrySectionSelectionModel.id
    }

    private var keyPath: WritableKeyPath<AdventureModel, String> {
        switch actionType {
            case .name: \.[entryId].name
            case .content: \.[entryId].content
        }
    }
}

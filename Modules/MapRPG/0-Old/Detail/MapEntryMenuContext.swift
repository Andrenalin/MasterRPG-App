// @copyright André Trettin

import CoreRPG
import SwiftUI

struct MapEntryMenuContext: View {
    enum MenuType {
        case all
        case name
        case content
    }

    let editController: EditController
    let entrySectionEditorModel: EntrySectionEditorModel<MapModel>
    let menuType: MenuType

    @Environment(EntrySectionSelectionModel.self) private var entrySectionSelectionModel

    var body: some View {
        @Bindable var entryModel = entrySectionEditorModel

        MapEntryMapEditButton(editController: editController, entrySectionEditorModel: entrySectionEditorModel)

        if keyPath != nil {
            Divider()

            LinkSelectionButton(entryId: entryId, type: .audio, keyPath: keyPath, title: "Audio", bundle: .module, showLink: $entryModel.showLink)

            LinkSelectionButton(entryId: entryId, type: .dice, keyPath: keyPath, title: "Dice", bundle: .module, showLink: $entryModel.showLink)

            LinkSelectionButton(entryId: entryId, type: .map, keyPath: keyPath, title: "Map", bundle: .module, showLink: $entryModel.showLink)

            LinkSelectionButton(entryId: entryId, type: .pdf, keyPath: keyPath, title: "Pdf", bundle: .module, showLink: $entryModel.showLink)

            LinkSelectionButton(entryId: entryId, type: .photo, keyPath: keyPath, title: "Photo", bundle: .module, showLink: $entryModel.showLink)

            LinkSelectionButton(entryId: entryId, type: .table, keyPath: keyPath, title: "Table", bundle: .module, showLink: $entryModel.showLink)

            LinkSelectionButton(entryId: entryId, type: .value, keyPath: keyPath, title: "Value", bundle: .module, showLink: $entryModel.showLink)
        }
    }

    private var entryId: UUID {
        entrySectionSelectionModel.id
    }

    private var keyPath: WritableKeyPath<MapModel, String>? {
        switch menuType {
            case .all: nil
            case .name: \.[entryId].name
            case .content: \.[entryId].content
        }
    }
}

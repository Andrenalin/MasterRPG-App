// @copyright André Trettin

import CoreRPG
import SwiftUI

struct ValueValueColumn<Menu: View>: View {
    let root: CharacterRootModel
    let editController: EditController
    let entryId: UUID
    let menuView: () -> Menu

    var body: some View {
        //let _ = Self._printChanges()

        DisclosureGroupTV(isExpanded: editController.editorModel.isExpanded(for: entryId)) {
            TextFieldInlineModelEditor(editController: editController, linkReplaceController: editController.contentEditLink(for: entryId), prompt: "Enter a value for the entry", bundle: .module)
        } label: {
            ValueEntryValue(root: root, editController: editController, itemId: editController.model.id, entryId: entryId)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(.rect)
                .contextMenu {
                    menuView()
                }
        }
    }
}

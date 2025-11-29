// @copyright André Trettin

import CoreRPG
import SwiftUI

struct ValueNameColumn<Menu: View>: View {
    let root: CharacterRootModel
    let editController: EditController
    let entryId: UUID
    let menuView: () -> Menu

    var body: some View {
        //let _ = Self._printChanges()
        
        DisclosureGroupTV(isExpanded: editController.editorModel.isExpanded(for: entryId)) {
            TextFieldInlineModelEditor(editController: editController, linkReplaceController: editController.nameEditLink(for: entryId), prompt: "Enter a name for the entry", bundle: .module)
        } label: {
            ValueEntryName(root: root, editController: editController, itemId: editController.model.id, entryId: entryId)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(.rect)
                .contextMenu {
                    menuView()
                }
        }
    }
}

#Preview {
    VStack {
        ValueNameColumn(root: .preview, editController: .preview, entryId: ValueEntryModel.previewId) {
            Text("Menu")
        }
        Divider()
        ValueNameColumn(root: .preview, editController: .preview, entryId: ValueEntryModel.previewId) {
            Text("Menu")
        }
    }
    .environment(CharacterRootModel.preview)
}

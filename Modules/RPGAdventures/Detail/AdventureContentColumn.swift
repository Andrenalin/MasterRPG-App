// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct AdventureContentColumn<Menu: View>: View {
    let root: AdventureRoot
    let editController: EditController
    let entryId: UUID
    let menuView: () -> Menu

    var body: some View {
        @Bindable var model = editController.model
        DisclosureGroupTV(isExpanded: editController.editorModel.isExpanded(for: entryId)) {
            TextFieldInlineModelEditor(editController: editController, linkReplaceController: editController.contentEditLink(for: entryId), prompt: "Enter some content for the entry", bundle: .module)
        } label: {
            AdventureEntryContent(root: root, editController: editController, entryId: entryId)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .contextMenu {
                    menuView()
                }
        }
    }
}

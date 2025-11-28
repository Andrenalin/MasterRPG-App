// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct AdventureNameColumn<Menu: View>: View {
    let root: AdventureRootModel
    let editController: EditController
    let entryId: UUID
    let menuView: () -> Menu

    var body: some View {
        @Bindable var model = editController.model
        DisclosureGroupTV(isExpanded: editController.editorModel.isExpanded(for: entryId)) {
            TextFieldInlineEditor(editController: editController, model: $model[entryId].name, prompt: "Enter a name for the entry", bundle: .module)
        } label: {
            Text(model[entryId].name)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .contextMenu {
                    menuView()
                }
        }
    }
}

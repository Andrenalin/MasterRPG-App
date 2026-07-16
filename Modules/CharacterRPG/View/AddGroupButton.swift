// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AddGroupButton: View {
    let root: CharacterRootModel
    let model: ValueModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            root.editController.setCurrentItem(to: ItemRowTreeModel(itemId: model.id, typeId: root.config.module))
            let itemId = model.id
            Task {
                let entryId = await root.editController.addNewGroup(itemId: itemId)
                withAnimation(reduceMotion ? nil : .default) {
                    root.editController.editorModel.sheetEditorModel.entryId = entryId
                }
                try? await Task.sleep(for: .seconds(0.25))
                root.editController.editorModel.sheetEditorModel.scrollEntryId = entryId
            }
        } label: {
            Label {
                Text("Add new Group", bundle: .module)
            } icon: {
                Image(systemName: "plus.square.fill.on.square.fill")
            }
        }
    }
}

#Preview(traits: .mockData) {
    AddGroupButton(root: .preview, model: .preview)
}

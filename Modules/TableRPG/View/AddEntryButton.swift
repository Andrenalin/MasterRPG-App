// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AddEntryButton: View {
    let root: TableRootModel
    let model: TableModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .default) {
                root.editController.setCurrentItem(
                    to: ItemRowTreeModel(itemId: model.id, typeId: root.config.module)
                )
                let entryId = root.editController.addNewEntry(itemId: model.id)
                root.editController.editorModel.sheetEditorModel.entryId = entryId
                Task {
                    try? await Task.sleep(for: .seconds(0.25))
                    root.editController.editorModel.sheetEditorModel.scrollEntryId = entryId
                }
            }
        } label: {
            Label {
                Text("Add new Entry", bundle: .module)
            } icon: {
                Image(systemName: "note.text.badge.plus")
            }
        }
    }
}

#Preview(traits: .mockData) {
    AddEntryButton(root: .preview, model: .preview)
}

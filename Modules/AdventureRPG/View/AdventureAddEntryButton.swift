// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AdventureAddEntryButton: View {
    let root: AdventureRootModel
    let model: AdventureModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .default) {
                let entryId = root.editController.addNewEntry(itemId: model.id)
                root.editController.setCurrentItem(to: ItemRowTreeModel(itemId: model.id, entryId: entryId, typeId: root.config.module))
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
    AdventureAddEntryButton(root: .preview, model: .preview)
}

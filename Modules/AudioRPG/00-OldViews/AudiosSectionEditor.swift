// @copyright André Trettin

import AndrenalinKit
import Observation
import SwiftUI

struct AudiosSectionEditor: View {
    let editController: EditController

    @Environment(AudioRootModel.self) private var root
    @Environment(SelectionSheetLinkModel.self) private var selectionSheetLinkModel

    var body: some View {
        @Bindable var model = editController.model
        ItemsSelectionEditor(editController: editController, model: $model.entries, title: "PLaylist", bundle: .module, value: .audio, minimumWidth: 200) {  entry in
            PlayListHiddenEditor(editController: editController, model: root.itemController.itemOrEmpty(for: entry.audioId))
        } selectorView: {
            root.viewController.viewSelect(root: root, filter: .all) {
                model.entries.map { ItemRowModel(itemId: $0.audioId, typeId: .audio) }
            } toggleSelection: { selection, _ in
                if let index = model.entries.firstIndex(where: { $0.audioId == selection.itemId }) {
                    model.entries.remove(at: index)
                } else {
                    model.entries.append(AudioEntryModel(id: UUID(), audioId: selection.itemId))
                }
            } dismissAction: {
                selectionSheetLinkModel.selection = false
            }
        } valueFactory: { audioId in
            AudioEntryModel(id: UUID(), audioId: audioId)
        }
    }
}

#Preview {
    AudiosSectionEditor(editController: .preview)
        .environment(AudioRootModel.preview)
}

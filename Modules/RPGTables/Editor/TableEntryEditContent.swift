// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct TableEntryEditContent: View {
    let editController: EditController
    let entrySectionEditorModel: EntrySectionEditorModel<TableModel>

    @Environment(TableRoot.self) private var root
    @Environment(EntrySectionSelectionModel.self) private var entrySectionSelectionModel

    var body: some View {
        @Bindable var model = editController.model
        Group {
            TextFieldEditor(editController: editController, model: $model[entryId].name, title: "Name", prompt: "Enter a name for the entry", bundle: .module)

            TextFieldControllerEditor(editController: editController, linkReplaceController: editController.contentEditLink(for: entryId), title: "Content", prompt: "Enter some content for the entry", bundle: .module)
                .contextMenu {
                    TableEntryMenuContext(editController: editController, entrySectionEditorModel: entrySectionEditorModel, menuType: .content)
                }
#if !os(tvOS)
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    TableEntrySwipeAction(editController: editController, entrySectionEditorModel: entrySectionEditorModel, actionType: .content)
                }
#endif
        }
    }
}

private extension TableEntryEditContent {
    var entryId: UUID {
        entrySectionSelectionModel.id
    }
}

// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct AdventureEntryEditContent: View {
    let editController: EditController
    let entrySectionEditorModel: EntrySectionEditorModel<AdventureModel>

    @Environment(AdventureRootModel.self) private var root
    @Environment(EntrySectionSelectionModel.self) private var entrySectionSelectionModel

    var body: some View {
        @Bindable var model = editController.model
        Group {
            TextFieldEditor(editController: editController, model: $model[entryId].name, title: "Name", prompt: "Enter a name for the entry", bundle: .module)

            TextFieldControllerEditor(editController: editController, linkReplaceController: editController.contentEditLink(for: entryId), title: "Content", prompt: "Enter some content for the entry", bundle: .module)
                .contextMenu {
                    AdventureEntryMenuContext(editController: editController, entrySectionEditorModel: entrySectionEditorModel,menuType: .content)
                }
#if !os(tvOS)
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    AdventureEntrySwipeAction(editController: editController, entrySectionEditorModel: entrySectionEditorModel, actionType: .content)
                }
#endif
        }
    }
}

private extension AdventureEntryEditContent {
    var entryId: UUID {
        entrySectionSelectionModel.id
    }
}

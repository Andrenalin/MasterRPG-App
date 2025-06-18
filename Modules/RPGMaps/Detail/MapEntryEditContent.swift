// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct MapEntryEditContent: View {
    let editController: EditController
    let entrySectionEditorModel: EntrySectionEditorModel<MapModel>

    @Environment(MapRoot.self) private var root
    @Environment(EntrySectionSelectionModel.self) private var entrySectionSelectionModel

    var body: some View {
        @Bindable var model = editController.model
        TextFieldEditor(editController: editController, model: $model[entryId].name, title: "Name", prompt: "Enter a name for the entry", bundle: .module)

        TextFieldControllerEditor(editController: editController, linkReplaceController: editController.contentEditLink(for: entryId), title: "Content", prompt: "Enter some content for the entry", bundle: .module)
            .contextMenu {
                MapEntryMenuContext(editController: editController, entrySectionEditorModel: entrySectionEditorModel, menuType: .content)
            }
#if !os(tvOS)
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                MapEntrySwipeAction(editController: editController, entrySectionEditorModel: entrySectionEditorModel, actionType: .content)
            }
#endif

        ToggleEditor(editController: editController, model: $model[entryId].isShown, title: "Shown", bundle: .module, icon: "eyes")

        UpdateMapPinEditor(editController: editController, entryId: entryId, pinId: nil)

        MapEntryMapEditButton(editController: editController, entrySectionEditorModel: entrySectionEditorModel)
    }
}

private extension MapEntryEditContent {
    var entryId: UUID {
        entrySectionSelectionModel.id
    }
}

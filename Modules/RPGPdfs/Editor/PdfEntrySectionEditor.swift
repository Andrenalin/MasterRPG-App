// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct PdfEntrySectionEditor: View {
    let editController: EditController
    
    @Environment(PdfRoot.self) private var root
    @State private var entrySectionEditorModel = EntrySectionEditorModel<PdfModel>()

    var body: some View {
        @Bindable var model = editController.model

        EntrySectionEditor(editControllable: editController, entrySectionEditorModel: entrySectionEditorModel) { entryId in
            Group {
                TextFieldEditor(editController: editController, model: $model[entryId].name, title: "Name", prompt: "Enter a name for the bookmark", bundle: .module)

                TextFieldEditor(editController: editController, model: $model[entryId].content, title: "Content", prompt: "Enter some content for the bookmark", bundle: .module)
            }
        } contentView: { entryId in
            EntryRow(item: ItemRowTreeModel(itemId: editController.model.id, entryId: entryId, typeId: root.itemController.itemDataModel.networkModule), isSelected: false, cacheItemListModel: editController.cacheItemListModel)
        } showLinkView: {
            EmptyView()
        } swipeActionView: { entryId in
            EmptyView()
        } menuView: { entryId in
            EmptyView()
        } linkActionView: {
            EmptyView()
        }
    }
}

#Preview {
    PdfEntrySectionEditor(editController: .preview)
        .environment(PdfRoot.preview)
        .environment(ListModel.preview)
}

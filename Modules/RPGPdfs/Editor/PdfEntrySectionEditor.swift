// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct PdfEntrySectionEditor: View {
    let editController: EditController
    
    @Environment(PdfRoot.self) private var root

    var body: some View {
        @Bindable var model = editController.model

        EntrySectionEditor(editControllable: editController) { entryId, showLink in
            Group {
                TextFieldEditor(editController: editController, model: $model[entryId].name, title: "Name", prompt: "Enter a name for the bookmark", bundle: .module)

                TextFieldEditor(editController: editController, model: $model[entryId].content, title: "Content", prompt: "Enter some content for the bookmark", bundle: .module)
            }
        } contentView: { entryId, showLink in
            EntryRow(item: ItemRowTreeModel(itemId: editController.model.id, entryId: entryId, typeId: root.itemController.itemDataModel.networkModule), isSelected: false, cacheItemListModel: editController.cacheItemListModel)
        } showLinkView: { linkValue in
            EmptyView()
        } swipeActionView: { entryId, showLink in
            EmptyView()
        } menuView: { entryId, selection, showLink in
            EmptyView()
        } linkActionView: { entryId, showLink in
            EmptyView()
        }
    }
}

#Preview {
    PdfEntrySectionEditor(editController: .preview)
        .environment(PdfRoot.preview)
        .environment(ListModel.preview)
}

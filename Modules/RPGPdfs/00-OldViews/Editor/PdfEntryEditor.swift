// @copyright André Trettin

#if !os(tvOS)

import AndrenalinKit
import SwiftUI

struct PdfEntryEditor: View {
    let root: PdfRootModel
    let editController: EditController

    var body: some View {
        EntryEditor(editControllable: editController) {
            contentView()
        } linkActionView: {
            linkActionView()
        }
    }
    
    @ViewBuilder
    func linkActionView() -> some View {
        EmptyView()
    }
    
    @ViewBuilder
    func contextMenuView(entryId: UUID) -> some View {
        ContextMenuEntryEditor(editControllable: editController, entryId: entryId) {
            EmptyView()
        }
    }
    
    @ViewBuilder
    func contentView() -> some View {
        @Bindable var item = editController.model
        @Bindable var editorModel = editController.editorModel
        Table(item.entries, selection: $editorModel.selected) {
            TableColumn(Text("Name", bundle: .module)) { entry in
                TableNameColumn(root: root, editController: editController, entryId: entry.id) {
                    contextMenuView(entryId: entry.id)
                }
            }
            .width(220)

            TableColumn(Text("Content", bundle: .module)) { entry in
                TableContentColumn(root: root, editController: editController, entryId: entry.id) {
                    contextMenuView(entryId: entry.id)
                }
            }
            .width(min: 32)
        }
    }
}

#endif

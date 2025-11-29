// @copyright André Trettin

import CoreRPG
import SwiftUI

struct TableContentColumn<Menu: View>: View {
    let root: TableRootModel
    let editController: EditController
    let entryId: UUID
    let menuView: () -> Menu

    @State private var isExpanded = false
    
    var body: some View {
        //let _ = Self._printChanges()

        DisclosureGroupTV(isExpanded: $isExpanded) {
            TextFieldInlineModelEditor(editController: editController, linkReplaceController: editController.contentEditLink(for: entryId), prompt: "Enter some content for the entry", bundle: .module)
        } label: {
            TableEntryContent(root: root, editController: editController, entryId: entryId)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(.rect)
                .contextMenu {
                    menuView()
                }
        }
        .onChange(of: editController.editorModel.expandedEntries) {
            let currentExpanded = editController.editorModel.expandedEntries[entryId, default: false]
            guard isExpanded != currentExpanded else { return }
            withAnimation { isExpanded = currentExpanded }
        }
    }
}

#Preview {
    TableContentColumn(root: .preview, editController: .preview, entryId: TableEntryModel.previewLinkId) {
        Text("Menu")
    }
}

// @copyright André Trettin

import SwiftUI

struct EntryEditorContent<LinkType: LinkDataTransferable>: View {
    let editController: any EntryDataEditable
    let editorModel: SheetEditorModel
    let itemId: UUID
    let editModel: TextEditModel
    let entry: any EntryDataAccessable
    let linkTypes: LinkType.Type
    
    @FocusState private var currentFocus: EntryEditorFocusField?

    var body: some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    EntryEditorHeaderView(
                        editController: editController,
                        editorModel: editorModel,
                        itemId: itemId,
                        editModel: editModel,
                        entry: entry,
                        linkTypes: linkTypes
                    )
                    
                    EntryNameEditor(editModel: editModel, currentFocus: $currentFocus)
                    
                    EntryContentEditor(editModel: editModel, currentFocus: $currentFocus)
                }
                .padding()
                .background {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.accentColor.opacity(0.95).gradient)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .containerShape(.rect(cornerRadius: 24, style: .continuous))
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .padding(32)
        }
        //.frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            currentFocus = .name
        }
    }
}

enum EntryEditorFocusField {
    case name
    case information
}

// @copyright André Trettin

import SwiftUI

struct EntryEditorContent<Header: View>: View {
    let entry: any EntryDataAccessable
    let editModel: TextEditModel
    let header: () -> Header
    
    @FocusState private var currentFocus: EntryEditorFocusField?

    var body: some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    header()
                    
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
        .contentShape(.rect)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            currentFocus = .name
        }
    }
}

enum EntryEditorFocusField {
    case name
    case information
}

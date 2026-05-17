// @copyright André Trettin

import SwiftUI

struct EntryContentEditor: View {
    let editModel: TextEditModel
    @FocusState.Binding var currentFocus: EntryEditorFocusField?

    var body: some View {
        Text("Description", bundle: .module)
            .font(.caption)

#if os(tvOS)
        @Bindable var editModel = editModel

        TextField(text: $editModel.text, prompt: Text("Add content", bundle: .module), axis: .vertical) {
            Text("Description", bundle: .module)
        }
        .frame(minHeight: 120, maxHeight: 200)
        .border(Color.accentColor.secondary)
        .padding(.bottom, 6)
        .focused($currentFocus, equals: .information)
#else
        TextEditorLinkView(model: editModel)
            .focused($currentFocus, equals: .information)
            .onChange(of: editModel.attributedText) {
                editModel.updateLinks()
            }
#endif
    }
}

#Preview {
    @Previewable @FocusState var focus: EntryEditorFocusField?
    
    EntryContentEditor(editModel: TextEditModel(linkRegisterController: nil), currentFocus: $focus)
}

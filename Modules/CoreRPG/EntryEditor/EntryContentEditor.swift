// @copyright André Trettin

import SwiftUI

struct EntryContentEditor: View {
    @Bindable var editModel: TextEditModel
    @FocusState.Binding var currentFocus: EntryEditorFocusField?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Description", bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

#if os(tvOS)
            TextField(text: $editModel.text, prompt: Text("Add content", bundle: .module), axis: .vertical) {
                Text("Description", bundle: .module)
            }
            .frame(minHeight: 120, maxHeight: 200)
            .border(Color.accentColor.secondary)
            .padding(.bottom, 6)
            .focused($currentFocus, equals: .information)
#else
            TextEditorLinkView(
                model: editModel,
                maxHeight: 200,
                isFocused: currentFocus == .information
            )
                .focused($currentFocus, equals: .information)
                .onChange(of: editModel.attributedText) { _, _ in
                    editModel.updateLinks()
                }
#endif
        }
    }
}

// MARK: - Previews

#Preview("Light Mode") {
    @Previewable @FocusState var focus: EntryEditorFocusField?
    @Previewable @State var model = TextEditModel(linkRegisterController: nil)
    
    VStack {
        EntryContentEditor(editModel: model, currentFocus: $focus)
            .padding()
    }
    .background(.background)
    .preferredColorScheme(.light)
    .onAppear {
        model.text = "Sample content with [link](test)"
        model.resetAttributedText()
    }
}

#Preview("Dark Mode") {
    @Previewable @FocusState var focus: EntryEditorFocusField?
    @Previewable @State var model = TextEditModel(linkRegisterController: nil)
    
    VStack {
        EntryContentEditor(editModel: model, currentFocus: $focus)
            .padding()
    }
    .background(Color.black)
    .preferredColorScheme(.dark)
    .onAppear {
        model.text = "Sample content with [link](test)"
        model.resetAttributedText()
    }
}

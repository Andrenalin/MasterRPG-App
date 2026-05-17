// @copyright André Trettin

import SwiftUI

struct EntryNameEditor: View {
    let editModel: TextEditModel
    @FocusState.Binding var currentFocus: EntryEditorFocusField?

    var body: some View {
        @Bindable var editModel = editModel

        Text("Name", bundle: .module)
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)

        HStack {
            TextField(text: $editModel.name, prompt: Text("Enter a name", bundle: .module)) {
                Text("Name", bundle: .module)
            }
            .focused($currentFocus, equals: .name)
            .labelsHidden()
            .textFieldStyle(.plain)

            Button {
                editModel.name = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .opacity(editModel.name.isEmpty ? 0: 1)
            .animation(.default, value: editModel.name.isEmpty)
            .contentTransition(.symbolEffect(.automatic))
        }
        .padding(6)
#if os(iOS) || os(visionOS)
        .background(Color(.systemGray6))
#elseif os(tvOS)
        .background(Color(.black))
#else
        .background(Color(.controlBackgroundColor))
#endif
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.secondary, lineWidth: 1)
        }
    }
}

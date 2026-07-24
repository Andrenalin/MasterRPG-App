// @copyright André Trettin

import SwiftUI

struct EntryNameEditor: View {
    @Bindable var editModel: TextEditModel
    @FocusState.Binding var currentFocus: EntryEditorFocusField?
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Name", bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                AttributedTextEditorSurface(
                    text: $editModel.attributedName,
                    links: editModel.nameLinks,
                    minHeight: 44,
                    maxHeight: 44,
                    isFocused: currentFocus == .name,
                    layout: .singleLine
                )
                .focused($currentFocus, equals: .name)
                .accessibilityIdentifier("entry.editor.name")
                .autocorrectionDisabled()
                .textInputAutocapitalizationAll(.sentences)
                .overlay(alignment: .leading) {
                    if editModel.attributedName.characters.isEmpty {
                        Text("Enter a name", bundle: .module)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .allowsHitTesting(false)
                    }
                }
                .onChange(of: editModel.attributedName) {
                    editModel.updateNameLinks()
                }

                if !editModel.attributedName.characters.isEmpty {
                    Button {
                        editModel.name = ""
                        editModel.attributedName = AttributedString("")
                    } label: {
                        Label {
                            Text("Clear name", bundle: .module)
                        } icon: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .labelStyle(.iconOnly)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .animation(
            accessibilityReduceMotion ? nil : .snappy(duration: 0.2),
            value: editModel.attributedName.characters.isEmpty
        )
    }
}

// MARK: - Previews

#Preview("Empty - Dark") {
    @Previewable @FocusState var focus: EntryEditorFocusField?
    @Previewable @State var model = TextEditModel(linkRegisterController: nil)
    
    EntryNameEditor(editModel: model, currentFocus: $focus)
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
}

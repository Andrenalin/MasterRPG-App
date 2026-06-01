// @copyright André Trettin

import SwiftUI

struct EntryNameEditor: View {
    @Bindable var editModel: TextEditModel
    @FocusState.Binding var currentFocus: EntryEditorFocusField?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Name", bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                TextField(text: $editModel.name, prompt: Text("Enter a name", bundle: .module)) {
                    Text("Name", bundle: .module)
                }
                .focused($currentFocus, equals: .name)
                .labelsHidden()
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalizationAll(.sentences)

                if !editModel.name.isEmpty {
                    Button {
                        editModel.name = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .imageScale(.medium)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Clear name", bundle: .module))
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(8)
            .background(adaptiveBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: 1)
            }
        }
        .animation(.snappy(duration: 0.2), value: editModel.name.isEmpty)
    }
    
    private var adaptiveBackgroundColor: Color {
#if os(iOS) || os(visionOS)
        colorScheme == .dark ? Color.black : Color.white
#elseif os(tvOS)
        Color.black.opacity(colorScheme == .dark ? 0.3 : 0.5)
#else
        Color(nsColor: .controlBackgroundColor)
#endif
    }
    
    private var strokeColor: Color {
        currentFocus == .name ? Color.accentColor : Color.secondary.opacity(0.3)
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

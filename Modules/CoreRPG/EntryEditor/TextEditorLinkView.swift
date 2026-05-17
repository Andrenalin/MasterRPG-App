// @copyright André Trettin

import SwiftUI

public struct TextEditorLinkView: View {
    public init(model: TextEditModel, maxHeight: CGFloat = 200.0) {
        self.model = model
        self.maxHeight = maxHeight
    }
    
    public let model: TextEditModel
    let maxHeight: CGFloat
    
    @State private var selection: AttributedTextSelection = .init()
    
    public var body: some View {
        @Bindable var model = model
#if os(tvOS)
        TextField(text: $model.text, prompt: Text("Add content", bundle: .module), label: {
            Text("Edit content", bundle: .module)
        })
        .labelsHidden()
        .frame(minHeight: 120, maxHeight: maxHeight)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.secondary)
        }
        .padding(.bottom, 6)
#else
        ZStack {
#if os(macOS)
            Color(nsColor: .controlBackgroundColor)
#endif
            TextEditor(text: $model.attributedText, selection: $selection)
                .attributedTextFormattingDefinition(ContentFormattingDefinition(links: Set(model.links.map(\.id))))
#if !os(macOS)
                .textInputAutocapitalization(.sentences)
                .writingToolsBehavior(.complete)
#endif
                .autocorrectionDisabled(true)
                //.frame(minHeight: 120, maxHeight: maxHeight)
                .padding(valueFor(iOS: 0, macOS: 4, tvOS: 0, visionOS: 0))
        }
        .background {
            Color.clear
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.secondary)
        }
        .frame(minHeight: 120, maxHeight: maxHeight)
#endif
    }
}

#Preview {
    @Previewable @State var model: TextEditModel = .init(linkRegisterController: .fake)
    
    Color.clear
        .background {
            Rectangle().fill(Color.blue.gradient)
        }
        .overlay {
            TextEditorLinkView(model: model, maxHeight: 200)
                .padding()
        }
        .onAppear() {
            model.name = "Hello"
            model.text = "Long Text"
            model.resetAttributedText()
        }
}

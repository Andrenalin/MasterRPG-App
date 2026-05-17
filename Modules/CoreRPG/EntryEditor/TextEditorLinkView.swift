// @copyright André Trettin

import SwiftUI

struct TextEditorLinkView: View {
    @Bindable public var model: TextEditModel
    let maxHeight: CGFloat
    
    @State private var selection: AttributedTextSelection = .init()
    @State private var formattingDefinition: ContentFormattingDefinition?
    @Environment(\.colorScheme) private var colorScheme
    
    public var body: some View {
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
        let currentDefinition = formattingDefinition ?? ContentFormattingDefinition(links: [], colorScheme: colorScheme)
        
        ZStack {
#if os(macOS)
            Color(nsColor: .controlBackgroundColor)
#endif
            TextEditor(text: $model.attributedText, selection: $selection)
                .attributedTextFormattingDefinition(currentDefinition)
                .textInputAutocapitalizationAll(.sentences)
                .writingToolsBehavior(.complete)
                .autocorrectionDisabled(true)
                .padding(valueFor(iOS: 0, macOS: 4, tvOS: 0, visionOS: 0))
                .onChange(of: model.links) { _, newLinks in
                    updateFormattingDefinition(links: newLinks)
                }
                .onChange(of: colorScheme) { _, _ in
                    updateFormattingDefinition(links: model.links)
                }
                .onAppear {
                    updateFormattingDefinition(links: model.links)
                }
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
    
    private func updateFormattingDefinition(links: [LinkRegisterModel]) {
        let linkIds = Set(links.map(\.id))
        formattingDefinition = ContentFormattingDefinition(links: linkIds, colorScheme: colorScheme)
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

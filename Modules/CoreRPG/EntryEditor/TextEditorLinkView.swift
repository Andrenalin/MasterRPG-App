// @copyright André Trettin

import SwiftUI

struct TextEditorLinkView: View {
    @Bindable public var model: TextEditModel
    let maxHeight: CGFloat

    let isFocused: Bool

    init(model: TextEditModel, maxHeight: CGFloat, isFocused: Bool = false) {
        self.model = model
        self.maxHeight = maxHeight
        self.isFocused = isFocused
    }
    
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
        AttributedTextEditorSurface(
            text: $model.attributedText,
            links: model.links,
            minHeight: 120,
            maxHeight: maxHeight,
            isFocused: isFocused
        )
#endif
    }
}

struct AttributedTextEditorSurface: View {
    enum Layout {
        case singleLine
        case multiline
    }

    @Binding var text: AttributedString

    let links: [LinkRegisterModel]
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let isFocused: Bool
    var layout: Layout = .multiline

    @Environment(\.appTheme) private var theme

    var body: some View {
        TextEditor(text: $text)
            .attributedTextFormattingDefinition(
                ContentFormattingDefinition(
                    links: Set(links.map(\.id)),
                    foregroundColor: theme.foregroundColor,
                    linkBackgroundColor: theme.accentColor.opacity(0.65)
                )
            )
            .font(.body)
            .foregroundStyle(theme.foregroundColor)
            .textEditorStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(.clear)
            .writingToolsBehavior(.complete)
            .contentMargins(.horizontal, 12, for: .scrollContent)
            .contentMargins(.vertical, verticalContentMargin, for: .scrollContent)
            .scrollIndicators(.hidden)
            .frame(
                minHeight: minHeight,
                idealHeight: layout == .singleLine ? minHeight : maxHeight,
                maxHeight: maxHeight
            )
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.panelColor.opacity(0.5))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isFocused
                            ? Color.accentColor
                            : theme.secondaryForegroundColor.opacity(0.35),
                        lineWidth: isFocused ? 2 : 1
                    )
            }
            .clipShape(.rect(cornerRadius: 14, style: .continuous))
    }

    private var verticalContentMargin: CGFloat {
        switch layout {
        case .singleLine:
            valueFor(iOS: 10, macOS: 11, tvOS: 0, visionOS: 10)
        case .multiline:
            10
        }
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

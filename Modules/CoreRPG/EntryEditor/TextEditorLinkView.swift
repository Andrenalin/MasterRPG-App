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
        .frame(minHeight: 60, maxHeight: maxHeight)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.secondary)
        }
        .padding(.bottom, 6)
#else
        AttributedTextEditorSurface(
            text: $model.attributedText,
            links: model.links,
            minHeight: 60,
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

#if os(macOS)
    // Bumped whenever normalizeLinkFormatting() has to correct stale colors while the
    // editor isn't focused, forcing TextEditor's NSTextView to be torn down and recreated.
    // See normalizeLinkFormatting() for why this is necessary.
    @State private var editorGeneration = 0
#endif

    var body: some View {
#if os(tvOS)
        EmptyView()
#else
        TextEditor(text: $text)
#if os(macOS)
            .id(editorGeneration)
#endif
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
#if os(macOS)
            // On macOS, TextEditor only re-runs attributedTextFormattingDefinition's
            // constraints when a real edit invalidates the `linkContent` attribute
            // (see LinkContentAttribute.invalidationConditions); a programmatic bulk
            // assignment of `text` (e.g. on first load) doesn't trigger that pass, so
            // link highlights stay unstyled until the user types something. Apply the
            // same constraints ourselves so the highlight shows immediately.
            .onChange(of: text, initial: true) { _, _ in normalizeLinkFormatting() }
            .onChange(of: links, initial: true) { _, _ in normalizeLinkFormatting() }
#endif
#if os(macOS)
            // contentMargins(_:_:for:.scrollContent) has no visible effect on the vertical
            // axis for TextEditor on macOS; padding is the reliable way to inset the text here.
            .padding(.vertical, verticalContentMargin)
            .padding(.horizontal, layout == .multiline ? 4 : 8)
#else
            .contentMargins(.vertical, verticalContentMargin, for: .scrollContent)
            .contentMargins(.horizontal, 8, for: .scrollContent)
#endif
            .scrollIndicators(.hidden)
            .frame(
                minHeight: minHeight,
                idealHeight: layout == .singleLine ? minHeight : maxHeight,
                maxHeight: maxHeight
            )
            .background {
                RoundedRectangle(cornerRadius: ResolvedAppTheme.panelCornerRadius, style: .continuous)
                    .fill(theme.panelColor.opacity(0.5))
            }
            .overlay {
                RoundedRectangle(cornerRadius: ResolvedAppTheme.panelCornerRadius, style: .continuous)
                    .strokeBorder(
                        isFocused
                        ? Color.accentColor
                        : theme.secondaryForegroundColor.opacity(0.35),
                        lineWidth: isFocused ? 2 : 1
                    )
            }
#if !os(macOS)
            .clipShape(.rect(cornerRadius: ResolvedAppTheme.panelCornerRadius, style: .continuous))
#endif

#endif
    }

#if os(macOS)
    private func normalizeLinkFormatting() {
        let definition = ContentFormattingDefinition(
            links: Set(links.map(\.id)),
            foregroundColor: theme.foregroundColor,
            linkBackgroundColor: theme.accentColor.opacity(0.65)
        )

        var normalized = text
        for run in normalized.runs {
            var container = run.attributes
            definition.constrain(&container)
            normalized[run.range].setAttributes(container)
        }

        guard normalized != text else { return }
        text = normalized

        // Correcting the AttributedString's attributes alone isn't enough on macOS: the
        // NSTextView TextEditor creates can leave the previous (unstyled) glyphs on screen
        // even though the underlying text storage is now correct - a resize doesn't force
        // it to redraw, but losing key window focus does, which shows this is a stale
        // display/glyph-cache issue rather than a data issue. Recreating the text view is
        // the only reliable way to force it to redraw with the corrected colors. Only do
        // this while unfocused so we never yank the cursor out from under an active edit.
        guard !isFocused else { return }
        editorGeneration += 1
    }
#endif

    private var verticalContentMargin: CGFloat {
        switch layout {
        case .singleLine:
            valueFor(iOS: 10, macOS: 12, tvOS: 0, visionOS: 10)
        case .multiline:
            8
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

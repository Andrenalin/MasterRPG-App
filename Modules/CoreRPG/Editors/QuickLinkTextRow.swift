// @copyright André Trettin

import SwiftUI

struct QuickLinkTextRow<EntryViewModel: ItemLinkEditable>: View {
    init(linkControllable: LinkControllable, model: EntryViewModel, original: Bool) {
        self.linkControllable = linkControllable
        self.model = model
        self.original = original
        _linkTextModel = State(wrappedValue: LinkHighlightTextModel(linkControllable: linkControllable, text: model.textLinkContent, highlightedText: nil, toggler: nil, shareResult: nil, editAction: { _ in !original }))
    }

    let linkControllable: LinkControllable
    let model: EntryViewModel
    let original: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var linkTextModel: LinkHighlightTextModel

    var body: some View {
        LinkHighlightTextView(model: linkTextModel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(original ? .black : .white)
            .rowColorBackground(isSelected: false, backgroundColor: rowColor)
            .onChange(of: model.textLinkContent, initial: false) {
                withAnimation { linkTextModel.reset(text: model.textLinkContent) }
            }
    }

    private var rowColor: Color {
        if original {
            return colorScheme == .dark ? .gray : .gray.opacity(0.25)
        }
        return colorScheme == .dark ? .black : .primary
    }
}

#Preview {
    QuickLinkTextRow(
        linkControllable: FakeLinkController.fake,
        model: QuickLinkPreviewEntry(textLinkContent: "The [forgotten shrine](RPG://ADVENTURE/preview) awaits."),
        original: true
    )
    .padding()
}

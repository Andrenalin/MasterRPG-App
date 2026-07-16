// @copyright André Trettin

import SwiftUI

struct QuickLinkTextRow<EntryViewModel: ItemLinkEditable>: View {
    let linkControllable: LinkControllable
    let model: EntryViewModel
    let original: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var _linkTextModel: LinkHighlightTextModel?

    var body: some View {
        LinkHighlightTextView(model: linkTextModel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(original ? .black : .white)
            .rowColorBackground(isSelected: false, backgroundColor: rowColor)
            .onChange(of: model.textLinkContent, initial: false) {
                updateEntryValues()
            }
    }

    private var linkTextModel: LinkHighlightTextModel {
        guard let linkModel = _linkTextModel else {
            return updateEntryValues()
        }
        return linkModel
    }

    @discardableResult
    private func updateEntryValues() -> LinkHighlightTextModel {
        let entryText = model.textLinkContent
        if let linkModel = _linkTextModel {
            withAnimation { linkModel.reset(text: entryText) }
            return linkModel
        } else {
            let linkModel = LinkHighlightTextModel(linkControllable: linkControllable, text: entryText, highlightedText: nil, toggler: nil, shareResult: nil, editAction: { _ in !original })
            Task {
                _linkTextModel = linkModel
            }
            return linkModel
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

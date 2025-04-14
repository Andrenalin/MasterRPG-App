// @copyright André Trettin

import SwiftUI

struct DescriptionItemRow: View {
    let itemId: UUID
    let description: String
    let cacheItemListModel: CacheItemListModel

    @Environment(ListModel.self) private var listModel

    var body: some View {
        Group {
            if !description.isEmpty {
                LinkHighlightTextView(model: linkTextModel)
                    .foregroundStyle(.tertiary)
                    .font(.footnote)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
            }
        }
    }

    private var linkTextModel: LinkHighlightTextModel {
        guard let linkModel = cacheItemListModel.itemLink(cacheType: .description, itemId: itemId) else {
            let model = LinkHighlightTextModel(linkControllable: nil, text: description.markDownText(), highlightedText: listModel.searchText)
            cacheItemListModel.setItemLink(cacheType: .description, itemId: itemId, linkModel: model)
            return model
        }
        if description.markDownText() != linkModel.text  {
            linkModel.reset(text: description.markDownText())
        }
        return linkModel
    }
}

#Preview {
    DescriptionItemRow(itemId: UUID(), description: "Very long desciption view text for fun", cacheItemListModel: CacheItemListModel())
}

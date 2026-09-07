// @copyright André Trettin

import SwiftUI

struct DescriptionItemNewRow: View, Equatable {
    let itemId: UUID
    let description: String
    let cacheItemListModel: CacheItemListModel
    let searchModel: SearchModel

    /// `cacheItemListModel` is a shared cache reference passed down unchanged across redraws,
    /// not row content, so it's excluded — see `NameItemNewRow`'s matching conformance and
    /// CODE_AUDIT §8.6.
    static func == (lhs: DescriptionItemNewRow, rhs: DescriptionItemNewRow) -> Bool {
        lhs.itemId == rhs.itemId
            && lhs.description == rhs.description
            && lhs.searchModel.searchText == rhs.searchModel.searchText
    }

    var body: some View {
        Group {
            if !description.isEmpty {
                LinkHighlightTextView(model: linkTextModel)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    private var linkTextModel: LinkHighlightTextModel {
        guard let linkModel = cacheItemListModel.itemLink(cacheType: .description, itemId: itemId) else {
            let model = LinkHighlightTextModel(linkControllable: nil, text: description.markDownText(), highlightedText: searchModel.searchText)
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
    DescriptionItemNewRow(itemId: UUID(), description: "Very long desciption view text for fun", cacheItemListModel: CacheItemListModel(), searchModel: SearchModel.preview())
}

// @copyright André Trettin

import SwiftUI

struct DescriptionItemRow: View {
    let itemId: UUID
    let description: String
    let cacheItemListModel: CacheItemListModel

    @Environment(SearchModel.self) private var searchModel

    var body: some View {
        let _ = Self._printChanges()
        Group {
            if !description.isEmpty {
                LinkHighlightTextView(model: linkTextModel)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    private var linkTextModel: LinkHighlightTextModel {
        guard let linkModel = cacheItemListModel.itemLink(cacheType: .description, itemId: itemId) else {
            let model = LinkHighlightTextModel(text: description.markDownText(), highlightedText: searchModel.searchText)
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

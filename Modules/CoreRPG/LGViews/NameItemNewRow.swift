// @copyright André Trettin

import SwiftUI

struct NameItemNewRow: View {
    let itemId: UUID
    let name: String
    let cacheItemListModel: CacheItemListModel
    let listDisplayModel: ListDisplayModel
    let searchModel: SearchModel
    
    var body: some View {
        LinkHighlightTextView(model: linkTextModel)
            .foregroundStyle(name.isEmpty ? .secondary : .primary)
            .lineLimit(listDisplayModel.displayMode == .compact ? 2 : 1)
    }

    private var linkTextModel: LinkHighlightTextModel {
        let nameText = name.isEmpty ? nameNotSet : name.markDownText()
        guard let linkModel = cacheItemListModel.itemLink(cacheType: .name, itemId: itemId) else {
            let model = LinkHighlightTextModel(linkControllable: nil, text: nameText, highlightedText: searchModel.searchText)
            cacheItemListModel.setItemLink(cacheType: .name, itemId: itemId, linkModel: model)
            return model
        }
        if nameText != linkModel.text {
            linkModel.reset(text: nameText)
        }
        return linkModel
    }
    
    public var nameNotSet: String {
        String(localized: "Untitled", bundle: .module).localizedString
    }
}


#Preview {
    @Previewable @State var searchText: String = "cool"
    @Previewable @State var searchModel = SearchModel.preview(search: "cool")
    @Previewable @State var itemId: UUID = UUID(uuidString: "226535FB-F20B-414C-BE4F-5438A77F6181")!
    @Previewable @State var cache = CacheItemListModel()

    VStack {
        TextField(text: $searchText) {
            Text("Search")
        }
        .onChange(of: searchText, initial: true) {
            searchModel.searchText = searchText
            cache.reset(search: searchText)
        }

        NameItemNewRow(itemId: itemId, name: "**Super cool Name** cool and more **cool**", cacheItemListModel: cache, listDisplayModel: ListDisplayModel(), searchModel: SearchModel.preview())
    }
}

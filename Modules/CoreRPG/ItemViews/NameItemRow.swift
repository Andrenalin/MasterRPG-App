// @copyright André Trettin

import SwiftUI

struct NameItemRow: View {
    let itemId: UUID
    let name: String
    let cacheItemListModel: CacheItemListModel
    
    @Environment(ListModel.self) private var listModel

    var body: some View {
        LinkHighlightTextView(model: linkTextModel)
            .foregroundStyle(.primary)
            .font(.headline)
            .lineLimit(1)
    }

    private var linkTextModel: LinkHighlightTextModel {
        guard let linkModel = cacheItemListModel.itemLink(cacheType: .name, itemId: itemId) else {
            let model = LinkHighlightTextModel(linkControllable: nil, text: name.markDownText(), highlightedText: listModel.searchText)
            cacheItemListModel.setItemLink(cacheType: .name, itemId: itemId, linkModel: model)
            return model
        }
        if name.markDownText() != linkModel.text  {             
            linkModel.reset(text: name.markDownText())
        }
        return linkModel
    }
}


#Preview {
    @Previewable @State var searchText: String = "cool"
    @Previewable @State var listModel = ListModel(searchToken: .all, categoryTags: [.all], listStoreName: "Test", hasChildren: false)
    @Previewable @State var itemId: UUID = UUID(uuidString: "226535FB-F20B-414C-BE4F-5438A77F6181")!
    @Previewable @State var cache = CacheItemListModel()

    VStack {
        TextField(text: $searchText) {
            Text("Search")
        }
        .onChange(of: searchText, initial: true) {
            listModel.searchText = searchText
        }

        NameItemRow(itemId: itemId, name: "**Super cool Name** cool and more **cool**", cacheItemListModel: cache)
    }
    .environment(listModel)
}

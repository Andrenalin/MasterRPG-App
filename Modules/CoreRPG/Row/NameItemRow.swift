// @copyright André Trettin

import SwiftUI

struct NameItemRow: View {
    let itemId: UUID
    let name: String
    let cacheItemListModel: CacheItemListModel
    
    @Environment(LinkRootController.self) private var linkController
    @Environment(SearchModel.self) private var searchModel

    var body: some View {
        LinkHighlightTextView(model: linkTextModel)
            .foregroundStyle(name.isEmpty ? .secondary : .primary)
            .lineLimit(1)
    }

    private var linkTextModel: LinkHighlightTextModel {
        let nameText = name.isEmpty ? nameNotSet : name.markDownText()
        guard let linkModel = cacheItemListModel.itemLink(cacheType: .name, itemId: itemId) else {
            let model = LinkHighlightTextModel(linkController: linkController, text: nameText, highlightedText: searchModel.searchText)
            cacheItemListModel.setItemLink(cacheType: .name, itemId: itemId, linkModel: model)
            return model
        }
        if nameText != linkModel.text {
            linkModel.reset(text: nameText)
        }
        return linkModel
    }
    
    private var nameNotSetResource: LocalizedStringResource {
        "Untitled"
    }
    
    public var nameNotSet: String {
        String(localized: nameNotSetResource).localizedString
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

        NameItemRow(itemId: itemId, name: "**Super cool Name** cool and more **cool**", cacheItemListModel: cache)
    }
    .environment(searchModel)
    .environment(DeviceRotationModel())
}

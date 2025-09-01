// @copyright André Trettin

import SwiftUI

public struct EntryRow: View {
    public init(entryId: UUID, name: String, content: String, cacheItemListModel: CacheItemListModel) {
        self.entryId = entryId
        self.name = name
        self.content = content
        self.cacheItemListModel = cacheItemListModel
    }

    let entryId: UUID
    let name: String
    let content: String
    let cacheItemListModel: CacheItemListModel
    
    @Environment(SearchModel.self) private var searchModel

    public var body: some View {
        LinkHighlightTextView(model: linkTextModel)
            .multilineTextAlignment(.leading)
    }

    private var linkTextModel: LinkHighlightTextModel {
        let nameText = name.isEmpty ? content : "\(name.markDownText()): \(content)"
        guard let linkModel = cacheItemListModel.itemLink(cacheType: .row, itemId: entryId) else {
            let model = LinkHighlightTextModel(text: nameText, highlightedText: searchModel.searchText)
            cacheItemListModel.setItemLink(cacheType: .row, itemId: entryId, linkModel: model)
            return model
        }
        if nameText != linkModel.text {
            linkModel.reset(text: nameText)
        }
        return linkModel
    }
}


#Preview {
    @Previewable @State var searchText: String = "cool"
    @Previewable @State var searchModel = SearchModel.preview(search: "cool")
    @Previewable @State var entryId: UUID = UUID(uuidString: "226535FB-F20B-414C-BE4F-5438A77F6181")!
    @Previewable @State var cache = CacheItemListModel()

    VStack {
        TextField(text: $searchText) {
            Text("Search")
        }
        .onChange(of: searchText, initial: true) {
            searchModel.searchText = searchText
            cache.reset(search: searchText)
        }

        EntryRow(entryId: entryId, name: "**Super cool Name** cool and more **cool**", content: "This is a cool content", cacheItemListModel: cache)
    }
    .environment(searchModel)
    .environment(DeviceRotationModel())
}

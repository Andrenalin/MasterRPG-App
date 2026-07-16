// @copyright André Trettin

import SwiftUI

struct ItemDetailPreview: View {
    private let fixture = FakeItemRootControllerFixture()
    private let model = FakeItemModel(
        id: .fixture1,
        name: "Ancient Map",
        category: .photo,
        description: "A weathered map showing the road to the lost keep.",
        tags: ["Map", "Quest"]
    )

    var body: some View {
        ItemDetailRootView(
            root: fixture.root,
            detailListController: fixture.folderListController,
            selectedModel: model,
            linkTypes: EmptyLinkTransferable.self
        ) {
            Text(verbatim: "Editor content")
        }
    }
}

#Preview("Item Detail") {
    ItemDetailPreview()
}

// @copyright André Trettin

import SwiftData
import SwiftUI

public struct ItemDetailOverlayView: View {
    public init(model: any ItemDataAccessable, cacheItemListModel: CacheItemListModel, listDisplayModel: ListDisplayModel, searchModel: SearchModel, fullHeader: Bool = false, onlyDescription: Bool = false, lines: Int = 20) {
        self.model = model
        self.listDisplayModel = listDisplayModel
        self.fullHeader = fullHeader
        self.onlyDescription = onlyDescription
        self.lines = lines
        self.cacheItemListModel = cacheItemListModel
        self.searchModel = searchModel
    }

    let model: any ItemDataAccessable
    let listDisplayModel: ListDisplayModel
    let fullHeader: Bool
    let onlyDescription: Bool
    let lines: Int
    let cacheItemListModel: CacheItemListModel
    let searchModel: SearchModel

    public var body: some View {
        VStack(alignment: .leading) {
            if fullHeader || onlyDescription == false {
                NameItemNewRow(itemId: model.id, name: model.name, cacheItemListModel: cacheItemListModel, listDisplayModel: listDisplayModel, searchModel: searchModel)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                HStack(spacing: 4) {
                    TagItemRow(tags: model.tags)
                }
            }
            if fullHeader || onlyDescription {
                DescriptionItemNewRow(itemId: model.id, description: model.description, cacheItemListModel: cacheItemListModel, searchModel: searchModel)
                    .foregroundStyle(.primary)
                    .font(.footnote)
                    .opacity(onlyDescription ? 1 : 0.8)
                    .lineLimit(lines)
            }
        }
    }
}

#Preview {
    ItemDetailOverlayView(
        model: FakeItemController.fake.itemOrEmpty(for: UUID()),
        cacheItemListModel: CacheItemListModel(),
        listDisplayModel: ListDisplayModel(),
        searchModel: FakeSearchController.fake.searchModel,
        fullHeader: true
    )
    .padding()
}

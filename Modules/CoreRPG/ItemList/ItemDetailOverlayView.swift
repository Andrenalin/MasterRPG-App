// @copyright André Trettin

import SwiftData
import SwiftUI

public struct ItemDetailOverlayView: View {
    public init(model: ItemDataModel) {
        self.model = model
        self.cacheItemListModel = CacheItemListModel()
    }
    
    let model: ItemDataModel
    let cacheItemListModel: CacheItemListModel

    public var body: some View {
        VStack(alignment: .leading) {
            NameItemRow(itemId: model.id, name: model.name, cacheItemListModel: cacheItemListModel)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            HStack {
                TagItemRow(tags: [model.category.title])
                
                TagItemRow(tags: model.tags)
            }
            DescriptionItemRow(itemId: model.id, description: model.information, cacheItemListModel: cacheItemListModel)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .opacity(0.8)
                .lineLimit(6)
        }
    }
}

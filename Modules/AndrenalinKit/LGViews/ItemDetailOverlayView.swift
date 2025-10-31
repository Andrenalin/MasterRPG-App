// @copyright André Trettin

import SwiftData
import SwiftUI

public struct ItemDetailOverlayView: View {
    public init(model: any ItemDataAccessable, fullHeader: Bool = false, onlyDescription: Bool = false) {
        self.model = model
        self.fullHeader = fullHeader
        self.onlyDesctiption = onlyDescription
        self.cacheItemListModel = CacheItemListModel()
    }
    
    let model: any ItemDataAccessable
    let fullHeader: Bool
    let onlyDesctiption: Bool
    let cacheItemListModel: CacheItemListModel

    public var body: some View {
        VStack(alignment: .leading) {
            if fullHeader || onlyDesctiption == false {
                NameItemNewRow(itemId: model.id, name: model.name, cacheItemListModel: cacheItemListModel)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                HStack {
                    TagItemRow(tags: [model.category.title])
                    
                    TagItemRow(tags: model.tags)
                }
            }
            if fullHeader || onlyDesctiption {
                DescriptionItemNewRow(itemId: model.id, description: model.description, cacheItemListModel: cacheItemListModel)
                    .foregroundColor(.primary)
                    .opacity(0.8)
                    .lineLimit(20)
            }
        }
    }
}

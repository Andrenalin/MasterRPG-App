// @copyright André Trettin

import SwiftData
import SwiftUI

public struct ItemDetailOverlayView: View {
    public init(model: any ItemDataAccessable, fullHeader: Bool = false, onlyDescription: Bool = false, lines: Int = 20) {
        self.model = model
        self.fullHeader = fullHeader
        self.onlyDescription = onlyDescription
        self.lines = lines
        self.cacheItemListModel = CacheItemListModel()
    }
    
    let model: any ItemDataAccessable
    let fullHeader: Bool
    let onlyDescription: Bool
    let lines: Int
    let cacheItemListModel: CacheItemListModel

    public var body: some View {
        VStack(alignment: .leading) {
            if fullHeader || onlyDescription == false {
                NameItemNewRow(itemId: model.id, name: model.name, cacheItemListModel: cacheItemListModel)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                HStack(spacing: 4) {
                    TagItemRow(tags: model.tags)
                }
            }
            if fullHeader || onlyDescription {
                DescriptionItemNewRow(itemId: model.id, description: model.description, cacheItemListModel: cacheItemListModel)
                    .foregroundStyle(.primary)
                    .font(.footnote)
                    .opacity(onlyDescription ? 1 : 0.8)
                    .lineLimit(lines)
            }
        }
    }
}

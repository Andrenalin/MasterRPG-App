// @copyright André Trettin

import SwiftData
import SwiftUI

public struct DetailOverlayView<Model>: View {
    public init(itemId: UUID, model: Model, nameKeyPath: KeyPath<Model, String>, categoryKeyPath: KeyPath<Model, ItemListCategory>, tagsKeyPath: KeyPath<Model, [String]>, descriptionKeyPath: KeyPath<Model, String>) {
        self.itemId = itemId
        self.model = model
        self.nameKeyPath = nameKeyPath
        self.categoryKeyPath = categoryKeyPath
        self.tagsKeyPath = tagsKeyPath
        self.descriptionKeyPath = descriptionKeyPath
        self.cacheItemListModel = CacheItemListModel()
    }
    
    let itemId: UUID
    let model: Model
    let nameKeyPath: KeyPath<Model, String>
    let categoryKeyPath: KeyPath<Model, ItemListCategory>
    let tagsKeyPath: KeyPath<Model, [String]>
    let descriptionKeyPath: KeyPath<Model, String>

    let cacheItemListModel: CacheItemListModel

    public var body: some View {
        VStack(alignment: .leading) {
            NameItemRow(itemId: itemId, name: model[keyPath: nameKeyPath], cacheItemListModel: cacheItemListModel)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            HStack {
                TagItemRow(tags: [model[keyPath: categoryKeyPath].title])
                
                TagItemRow(tags: model[keyPath: tagsKeyPath])
            }
            DescriptionItemRow(itemId: itemId, description: model[keyPath: descriptionKeyPath], cacheItemListModel: cacheItemListModel)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .opacity(0.8)
                .lineLimit(6)
        }
    }
}

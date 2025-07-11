// @copyright André Trettin

import SwiftUI

public struct ItemRow<Model, Thumbnail: View, Additional: View, ActionBar: View>: View {
    public init(itemId: UUID, model: Model, cacheItemListModel: CacheItemListModel, name: KeyPath<Model, String>, tags: KeyPath<Model, [String]>, description: KeyPath<Model, String>, isSelected: Bool, @ViewBuilder thumbnail: () -> Thumbnail = EmptyView.init, @ViewBuilder tagAdds: () -> Additional = EmptyView.init, @ViewBuilder actionBar: () -> ActionBar = EmptyView.init) {
        self.itemId = itemId
        self.model = model
        self.cacheItemListModel = cacheItemListModel
        nameKeyPath = name
        tagsKeyPath = tags
        descriptionKeyPath = description
        self.isSelected = isSelected
        self.thumbnail = thumbnail()
        additional = tagAdds()
        self.actionBar = actionBar()
    }
    
    let itemId: UUID
    let model: Model
    let cacheItemListModel: CacheItemListModel
    let nameKeyPath: KeyPath<Model, String>
    let tagsKeyPath: KeyPath<Model, [String]>
    let descriptionKeyPath: KeyPath<Model, String>
    let isSelected: Bool
    let thumbnail: Thumbnail
    let additional: Additional
    let actionBar: ActionBar
    
    public var body: some View {
        HStack(spacing: 4) {
            VStack(spacing: 0) {
                thumbnail
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: 4) {
                NameItemRow(itemId: itemId, name: model[keyPath: nameKeyPath], cacheItemListModel: cacheItemListModel)

                if model[keyPath: tagsKeyPath].count > 4 {
                    twoLineTagView
                } else {
                    allTagsView
                }
                
                actionBar
                
                DescriptionItemRow(itemId: itemId, description: model[keyPath: descriptionKeyPath], cacheItemListModel: cacheItemListModel)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    
    var tagContent: [String] {
        model[keyPath: tagsKeyPath]
    }
    
    var allTagsView: some View {
        HStack(spacing: 4) {
            additional
            
            TagItemRow(tags: tagContent)
        }
    }
    
    var tagFirstContent: [String] {
        let half = tagContent.count / 2
        guard half > 0 else {
            return []
        }
        return Array(tagContent[0..<half])
    }
    
    var tagSecondContent: [String] {
        let half = tagContent.count / 2
        let leftOver = tagContent.count - half
        guard leftOver > 0 else { return [] }
        
        return Array(tagContent[half...])
    }
    
    var twoLineTagView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                additional
                TagItemRow(tags: tagFirstContent)
            }
            
            HStack(spacing: 4) {
                TagItemRow(tags: tagSecondContent)
            }
        }
    }
}

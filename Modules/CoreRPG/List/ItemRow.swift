// @copyright André Trettin

import SwiftUI

public struct ItemRow<Model, Thumbnail: View, Additional: View, ActionBar: View>: View {
    public init(itemId: UUID, model: Model, cacheItemListModel: CacheItemListModel, name: KeyPath<Model, String>, tags: KeyPath<Model, [String]>, description: KeyPath<Model, String>, isSelected: Bool, isTrailing: Bool = false, @ViewBuilder thumbnail: () -> Thumbnail = EmptyView.init, @ViewBuilder tagAdds: () -> Additional = EmptyView.init, @ViewBuilder actionBar: () -> ActionBar = EmptyView.init) {
        self.itemId = itemId
        self.model = model
        self.cacheItemListModel = cacheItemListModel
        nameKeyPath = name
        tagsKeyPath = tags
        descriptionKeyPath = description
        self.isSelected = isSelected
        self.isTrailing = isTrailing
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
    let isTrailing: Bool
    let thumbnail: Thumbnail
    let additional: Additional
    let actionBar: ActionBar

    @Environment(ListModel.self) private var listModel

    public var body: some View {
        HStack(spacing: 4) {
            if !isTrailing {
                thumbView
            }

            VStack(alignment: .leading, spacing: 4) {
                NameItemRow(itemId: itemId, name: model[keyPath: nameKeyPath], cacheItemListModel: cacheItemListModel)

                if listModel.displayMode == .regular {
                    if model[keyPath: tagsKeyPath].count > 4 {
                        twoLineTagView
                    } else {
                        allTagsView
                    }

                    actionBar
                }
                if listModel.displayMode != .compact {
                    DescriptionItemRow(itemId: itemId, description: model[keyPath: descriptionKeyPath], cacheItemListModel: cacheItemListModel)
                }
            }
            .frame(minHeight: 64, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            if isTrailing {
                thumbView
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    
    private var thumbView: some View {
        VStack(spacing: 0) {
            thumbnail
        }
        .fixedSize(horizontal: true, vertical: false)
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

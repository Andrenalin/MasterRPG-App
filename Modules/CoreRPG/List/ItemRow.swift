// @copyright André Trettin

import SwiftUI

public struct ItemRow<Model, Thumbnail: View, ActionBar: View>: View {
    public init(itemId: UUID, model: Model, cacheItemListModel: CacheItemListModel, name: KeyPath<Model, String>, category: KeyPath<Model, ItemListCategory>, tags: KeyPath<Model, [String]>, description: KeyPath<Model, String>, isSelected: Bool = false, isTrailing: Bool = false, collectionCategory: ItemListCategory? = nil, @ViewBuilder thumbnail: () -> Thumbnail = EmptyView.init, @ViewBuilder actionBar: () -> ActionBar = EmptyView.init) {
        self.itemId = itemId
        self.model = model
        self.cacheItemListModel = cacheItemListModel
        self.nameKeyPath = name
        self.categoryKeyPath = category
        self.tagsKeyPath = tags
        self.descriptionKeyPath = description
        self.isSelected = isSelected
        self.isTrailing = isTrailing
        self.collectionCategory = collectionCategory
        self.thumbnail = thumbnail()
        self.actionBar = actionBar()
    }
    
    let itemId: UUID
    let model: Model
    let cacheItemListModel: CacheItemListModel
    let nameKeyPath: KeyPath<Model, String>
    let categoryKeyPath: KeyPath<Model, ItemListCategory>
    let tagsKeyPath: KeyPath<Model, [String]>
    let descriptionKeyPath: KeyPath<Model, String>
    let isSelected: Bool
    let isTrailing: Bool
    let collectionCategory: ItemListCategory?
    let thumbnail: Thumbnail
    let actionBar: ActionBar
    
    @Environment(ListModel.self) private var listModel
    
    public var body: some View {
        HStack(spacing: 4) {
            if !isTrailing {
                thumbView
            }
            
            VStack(alignment: .leading, spacing: 4) {
                NameItemRow(itemId: itemId, name: model[keyPath: nameKeyPath], cacheItemListModel: cacheItemListModel)
                    .font(.headline)
                
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
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                        .lineLimit(3)
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
}

private extension ItemRow {
    var thumbView: some View {
        VStack(spacing: 0) {
            if model[keyPath: categoryKeyPath] == .folder || model[keyPath: categoryKeyPath] == collectionCategory {
                Image(systemName: model[keyPath: categoryKeyPath].icon)
                    .font(.largeTitle)
            } else {
                thumbnail
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
    
    var tagContent: [String] {
        model[keyPath: tagsKeyPath]
    }
    
    var allTagsView: some View {
        HStack(spacing: 4) {
            if model[keyPath: categoryKeyPath] != .folder && model[keyPath: categoryKeyPath] != collectionCategory {
                CategoryItemRow(category: model[keyPath: categoryKeyPath])
            }
            
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
                if model[keyPath: categoryKeyPath] != .folder && model[keyPath: categoryKeyPath] != collectionCategory {
                    CategoryItemRow(category: model[keyPath: categoryKeyPath])
                }
                TagItemRow(tags: tagFirstContent)
            }
            
            HStack(spacing: 4) {
                TagItemRow(tags: tagSecondContent)
            }
        }
    }
}

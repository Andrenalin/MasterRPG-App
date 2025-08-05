// @copyright André Trettin

import SwiftUI

public struct ItemRow<Model, Thumbnail: View, ActionBar: View>: View {
    public init(itemId: UUID, model: Model, cacheItemListModel: CacheItemListModel, name: KeyPath<Model, String>, category: KeyPath<Model, ItemListCategory>, tags: KeyPath<Model, [String]>, description: KeyPath<Model, String>, isSelected: Bool = false, isTrailing: Bool = false, collectionCategory: ItemListCategory? = nil, @ViewBuilder thumbnail: () -> Thumbnail = EmptyView.init, @ViewBuilder actionBar: () -> ActionBar = EmptyView.init) {
        self.itemId = itemId
        self.model = model
        self.cacheItemListModel = cacheItemListModel
        self.name = name
        self.category = category
        self.tags = tags
        self.description = description
        self.isSelected = isSelected
        self.isTrailing = isTrailing
        self.collectionCategory = collectionCategory
        self.thumbnail = thumbnail()
        self.actionBar = actionBar()
    }
    
    let itemId: UUID
    let model: Model
    let cacheItemListModel: CacheItemListModel
    let name: KeyPath<Model, String>
    let category: KeyPath<Model, ItemListCategory>
    let tags: KeyPath<Model, [String]>
    let description: KeyPath<Model, String>
    let isSelected: Bool
    let isTrailing: Bool
    let collectionCategory: ItemListCategory?
    let thumbnail: Thumbnail
    let actionBar: ActionBar
    
    @Environment(ListModel.self) private var listModel
    
    public var body: some View {
        HStack(alignment: .center, spacing: 4) {
            specialCategoryIcon
            
            if !isTrailing {
                thumbView
            }
            
            VStack(alignment: .leading, spacing: 4) {
                NameItemRow(itemId: itemId, name: model[keyPath: name], cacheItemListModel: cacheItemListModel)
                    .font(.headline)
                
                if listModel.displayMode == .regular {
                    if model[keyPath: tags].count > 4 {
                        twoLineTagView
                    } else {
                        allTagsView
                    }
                    
                    actionBar
                }
                if listModel.displayMode != .compact {
                    DescriptionItemRow(itemId: itemId, description: model[keyPath: description], cacheItemListModel: cacheItemListModel)
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
            
            specialCategoryFolderIndicator
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private extension ItemRow {
    var isSpecialCategory: Bool {
        model[keyPath: category] == .folder || model[keyPath: category] == .drop || model[keyPath: category] == collectionCategory
    }
    
    @ViewBuilder
    var specialCategoryIcon: some View {
        if isSpecialCategory {
            Image(systemName: model[keyPath: category].icon)
                .font(.title)
        }
    }

    @ViewBuilder
    var specialCategoryFolderIndicator: some View {
        if model[keyPath: category] == .folder {
            Image(systemName: (listModel.subItemModels[itemId]?.isOpen ?? false) ? "chevron.down" : "chevron.right")
                .imageScale(.small)
                .padding(.trailing)
                .foregroundStyle((listModel.subItemModels[itemId]?.isOpen ?? false) ? Color.accentColor : Color.secondary)
                .contentShape(.rect)
                .onTapGesture {
                    guard model[keyPath: category] == .folder else { return }
                    let subModel = listModel.subItemModels[itemId, default: ListSubItemModel(id: itemId)]
                    subModel.isOpen.toggle()
                    withAnimation { listModel.subItemModels[itemId] = subModel }
                }
        }
    }

    @ViewBuilder
    var thumbView: some View {
        if !isSpecialCategory {
            VStack(spacing: 0) {
                thumbnail
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }
    
    var tagContent: [String] {
        model[keyPath: tags]
    }
    
    var allTagsView: some View {
        HStack(spacing: 4) {
            if model[keyPath: category] != .folder && model[keyPath: category] != collectionCategory {
                CategoryItemRow(category: model[keyPath: category])
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
                if model[keyPath: category] != .folder && model[keyPath: category] != collectionCategory {
                    CategoryItemRow(category: model[keyPath: category])
                }
                TagItemRow(tags: tagFirstContent)
            }
            
            HStack(spacing: 4) {
                TagItemRow(tags: tagSecondContent)
            }
        }
    }
}

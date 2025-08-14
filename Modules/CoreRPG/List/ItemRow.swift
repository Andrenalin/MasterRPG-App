// @copyright André Trettin

import SwiftUI

public struct ItemRow<Model: ModelType, Thumbnail: View, ActionBar: View>: View {
    public init(itemId: UUID, model: Model, cacheItemListModel: CacheItemListModel, isSelected: Bool = false, @ViewBuilder thumbnail: () -> Thumbnail = EmptyView.init, @ViewBuilder actionBar: () -> ActionBar = EmptyView.init) {
        self.itemId = itemId
        self.model = model
        self.cacheItemListModel = cacheItemListModel
        self.isSelected = isSelected
        self.thumbnail = thumbnail()
        self.actionBar = actionBar()
    }
    
    let itemId: UUID
    let model: Model
    let cacheItemListModel: CacheItemListModel
    let isSelected: Bool
    let thumbnail: Thumbnail
    let actionBar: ActionBar
    
    @Environment(ListModel.self) private var listModel
    @Environment(ListDisplayModel.self) private var listDisplayModel
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    
    public var body: some View {
        let _ = Self._printChanges()
        HStack(alignment: .center, spacing: 4) {
            specialCategoryIcon
            
            VStack(alignment: .leading, spacing: 4) {
                NameItemRow(itemId: itemId, name: model.name, cacheItemListModel: cacheItemListModel)
                    .font(.headline)
                
                if listDisplayModel.displayMode == .regular {
                    if model.tags.count > 4 {
                        twoLineTagView
                    } else {
                        allTagsView
                    }
                    
                    actionBar
                }
                if listDisplayModel.displayMode != .compact {
                    DescriptionItemRow(itemId: itemId, description: model.information, cacheItemListModel: cacheItemListModel)
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                        .lineLimit(3)
                }
            }
            .padding(.leading, isSpecialCategory ? 0 : 6)
            .frame(minHeight: 64, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            thumbView
            
            specialCategoryFolderIndicator
            specialAddIcon
        }
        .fixedSize(horizontal: false, vertical: true)
        .animation(.smooth, value: listDisplayModel.displayMode)
    }
}

private extension ItemRow {
    var isSpecialCategory: Bool {
        model.category == .folder || model.category == .drop || model.category == Model.collectionCategory
    }
    
    @ViewBuilder
    var specialCategoryIcon: some View {
        if isSpecialCategory {
            #if os(iOS)
            if model.category == .drop {
                Image(systemName: model.category.icon)
                    .font(.title)
                    .foregroundStyle(horizontalSizeClass == .compact ? .secondary : .primary)
            } else {
                Image(systemName: model.category.icon)
                    .font(.title)
            }
            #else
            Image(systemName: model.category.icon)
                .font(.title)
            #endif
        }
    }
    @ViewBuilder
    var specialAddIcon: some View {
        if model.category == .drop {
            Image(systemName: "checkmark.circle")
                .font(.title)
                .padding(.trailing)
        }
    }

    @ViewBuilder
    var specialCategoryFolderIndicator: some View {
        if model.category == .folder || model.category == Model.collectionCategory {
            Image(systemName: listModel.isFolderOpen(id: itemId) ? "chevron.down" : "chevron.right")
                .imageScale(.small)
                .padding(.trailing)
                .foregroundStyle(listModel.isFolderOpen(id: itemId) ? Color.accentColor : Color.secondary)
                .contentShape(.rect)
                .onTapGesture {
                    let subModel = listModel.subItemModel(for: itemId)
                    withAnimation { subModel.isOpen.toggle() }
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
        model.tags
    }
    
    var allTagsView: some View {
        HStack(spacing: 4) {
            if model.category != .folder && model.category != Model.collectionCategory {
                CategoryItemRow(category: model.category)
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
                if model.category != .folder && model.category != Model.collectionCategory {
                    CategoryItemRow(category: model.category)
                }
                TagItemRow(tags: tagFirstContent)
            }
            
            HStack(spacing: 4) {
                TagItemRow(tags: tagSecondContent)
            }
        }
    }
}


// @copyright André Trettin

import SwiftUI

public struct ItemRowView<Thumbnail: View, ActionBar: View>: View {
    public init(root: any ItemRootControllable, model: any ItemDataAccessable, cacheItemListModel: CacheItemListModel, isSelected: Bool = false, @ViewBuilder thumbnail: () -> Thumbnail = EmptyView.init, @ViewBuilder actionBar: () -> ActionBar = EmptyView.init) {
        self.root = root
        self.model = model
        self.cacheItemListModel = cacheItemListModel
        self.isSelected = isSelected
        self.thumbnail = thumbnail()
        self.actionBar = actionBar()
    }

    let root: any ItemRootControllable
    let model: any ItemDataAccessable
    let cacheItemListModel: CacheItemListModel
    let isSelected: Bool
    let thumbnail: Thumbnail
    let actionBar: ActionBar
    
    @Environment(ListDisplayModel.self) private var listDisplayModel
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    
    public var body: some View {
        HStack(alignment: .center, spacing: 4) {
            specialCategoryIcon
            
            VStack(alignment: .leading, spacing: 4) {
                NameItemNewRow(itemId: model.id, name: model.name, cacheItemListModel: cacheItemListModel)
                    .font(.headline)

                if listDisplayModel.displayMode == .regular {
                    TagDisplayView(
                        tags: model.tags,
                        category: model.category,
                        collectionCategory: root.itemControllable.collectionCategory
                    )
                }
                GameShareView(root: root, model: model) {
                    actionBar
                }

                if listDisplayModel.displayMode != .compact {
                    DescriptionItemNewRow(itemId: model.id, description: model.description, cacheItemListModel: cacheItemListModel)
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                        .lineLimit(3)
                }
            }
            .padding(.leading, isSpecialCategory ? 0 : 6)
            .frame(minHeight: listDisplayModel.imageHeight, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            thumbView
            
            specialAddIcon
        }
        .fixedSize(horizontal: false, vertical: true)
        .animation(.smooth, value: listDisplayModel.displayMode)
    }
}

private extension ItemRowView {
    var isSpecialCategory: Bool {
        model.category == .folder || model.category == .drop || model.category ==  root.itemControllable.collectionCategory
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
    var thumbView: some View {
        if !isSpecialCategory {
            thumbnail
        }
    }
}

// MARK: - Supporting Views

private struct TagDisplayView: View {
    let tags: [String]
    let category: ItemListCategory
    let collectionCategory: ItemListCategory

    var body: some View {
        if tags.count > 4 {
            TwoLineTagView(tags: tags, category: category, collectionCategory: collectionCategory)
        } else {
            HStack(spacing: 4) {
                TagItemRow(tags: tags)
            }
        }
    }
}

private struct TwoLineTagView: View {
    let tags: [String]
    let category: ItemListCategory
    let collectionCategory: ItemListCategory

    var body: some View {
        let half = tags.count / 2

        VStack(alignment: .leading, spacing: 4) {
            if half > 0 {
                HStack(spacing: 4) {
                    if category != .folder && category != collectionCategory {
                        CategoryItemRow(category: category)
                    }
                    TagItemRow(tags: Array(tags[0..<half]))
                }
            }

            if half < tags.count {
                HStack(spacing: 4) {
                    TagItemRow(tags: Array(tags[half...]))
                }
            }
        }
    }
}

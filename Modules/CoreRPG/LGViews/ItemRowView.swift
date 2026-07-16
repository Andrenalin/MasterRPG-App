// @copyright André Trettin

import SwiftUI

public struct ItemRowView<Thumbnail: View, ActionBar: View>: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    public init(root: any ItemRootControllable, model: any ItemDataAccessable, cacheItemListModel: CacheItemListModel, listDisplayModel: ListDisplayModel, searchModel: SearchModel, isSelected: Bool = false, @ViewBuilder thumbnail: () -> Thumbnail = EmptyView.init, @ViewBuilder actionBar: () -> ActionBar = EmptyView.init) {
        self.root = root
        self.model = model
        self.cacheItemListModel = cacheItemListModel
        self.listDisplayModel = listDisplayModel
        self.searchModel = searchModel
        self.isSelected = isSelected
        self.thumbnail = thumbnail()
        self.actionBar = actionBar()
    }

    let root: any ItemRootControllable
    let model: any ItemDataAccessable
    let cacheItemListModel: CacheItemListModel
    let listDisplayModel: ListDisplayModel
    let searchModel: SearchModel
    let isSelected: Bool
    let thumbnail: Thumbnail
    let actionBar: ActionBar
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    
    public var body: some View {
        HStack(alignment: .center, spacing: 4) {
            specialCategoryIcon
            
            VStack(alignment: .leading, spacing: 4) {
                NameItemNewRow(itemId: model.id, name: model.name, cacheItemListModel: cacheItemListModel, listDisplayModel: listDisplayModel, searchModel: searchModel)
                    .font(.headline)

                if listDisplayModel.displayMode == .regular {
                    TagDisplayView(
                        tags: model.tags,
                        category: model.category,
                        collectionCategory: root.itemControllable.collectionCategory
                    )
                }
                GameShareView(root: root, itemId: model.id) {
                    actionBar
                }

                if listDisplayModel.displayMode != .compact {
                    DescriptionItemNewRow(itemId: model.id, description: model.description, cacheItemListModel: cacheItemListModel, searchModel: searchModel)
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
        .animation(accessibilityReduceMotion ? nil : .smooth, value: listDisplayModel.displayMode)
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


#Preview("Item row") {
    ItemRowView(
        root: ItemRootController.fake,
        model: FakeItemModel(id: .fixture1, name: "Goblin Ambush", description: "A narrow bridge guarded by goblins.", tags: ["Encounter", "Dungeon"]),
        cacheItemListModel: CacheItemListModel(),
        listDisplayModel: ListDisplayModel(),
        searchModel: .preview()
    )
    .padding()
}

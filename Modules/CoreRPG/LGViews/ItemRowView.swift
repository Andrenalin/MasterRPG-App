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
            SpecialCategoryIconView(model: model, isSpecialCategory: isSpecialCategory)

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
            
            ThumbView(thumbnail: thumbnail, isSpecialCategory: isSpecialCategory)

            SpecialAddIconView(model: model)
        }
        .fixedSize(horizontal: false, vertical: true)
        .animation(accessibilityReduceMotion ? nil : .smooth, value: listDisplayModel.displayMode)
    }
}

private extension ItemRowView {
    var isSpecialCategory: Bool {
        model.category == .folder || model.category == .drop || model.category ==  root.itemControllable.collectionCategory
    }
}

extension ItemRowView: Equatable {
    /// This is the row rendered by every module's item list, so without an
    /// `Equatable` conformance it re-diffed its full body (icon, name, tag,
    /// share, description) on every unrelated state change the parent list
    /// observes. Compares the specific fields `body` actually reads —
    /// `thumbnail`/`actionBar` aren't compared, the same trade-off
    /// `NameItemNewRow`/`DescriptionItemNewRow` already make by excluding
    /// their own non-content parameters. See CODE_AUDIT_13 §8.4.
    public static func == (lhs: ItemRowView, rhs: ItemRowView) -> Bool {
        lhs.model.id == rhs.model.id
            && lhs.model.name == rhs.model.name
            && lhs.model.description == rhs.model.description
            && lhs.model.tags == rhs.model.tags
            && lhs.model.category == rhs.model.category
            && lhs.isSelected == rhs.isSelected
            && lhs.listDisplayModel.displayMode == rhs.listDisplayModel.displayMode
    }
}

private struct SpecialCategoryIconView: View {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    let model: any ItemDataAccessable
    let isSpecialCategory: Bool

    var body: some View {
        if isSpecialCategory {
            #if os(iOS)
            if model.category == .drop {
                Image(systemName: model.category.icon)
                    .font(.title)
                    .foregroundStyle(horizontalSizeClass == .compact ? .secondary : .primary)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: model.category.icon)
                    .font(.title)
                    .accessibilityHidden(true)
            }
            #else
            Image(systemName: model.category.icon)
                .font(.title)
                .accessibilityHidden(true)
            #endif
        }
    }
}

private struct SpecialAddIconView: View {
    let model: any ItemDataAccessable

    var body: some View {
        if model.category == .drop {
            Image(systemName: "checkmark.circle")
                .font(.title)
                .padding(.trailing)
                .accessibilityHidden(true)
        }
    }
}

private struct ThumbView<Thumbnail: View>: View {
    let thumbnail: Thumbnail
    let isSpecialCategory: Bool

    var body: some View {
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
    .environment(AppGameStateModel())
    .environment(\.locale, .init(identifier: "de"))
}

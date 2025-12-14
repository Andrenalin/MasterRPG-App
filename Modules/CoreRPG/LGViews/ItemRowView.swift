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
    
    @Environment(\.gameModus) private var gameModus
    @Environment(\.networkActions) private var networkActions
    @Environment(\.showGame) private var showGame
    @Environment(\.sharingFeatureActions) private var sharingFeatureActions
    
    public var body: some View {
        //let _ = Self._printChanges()
        HStack(alignment: .center, spacing: 4) {
            specialCategoryIcon
            
            VStack(alignment: .leading, spacing: 4) {
                NameItemNewRow(itemId: model.id, name: model.name, cacheItemListModel: cacheItemListModel)
                    .font(.headline)
                
                if listDisplayModel.displayMode == .regular {
                    if model.tags.count > 4 {
                        twoLineTagView
                    } else {
                        allTagsView
                    }
                }
                actionBarWithSharing

                if listDisplayModel.displayMode != .compact {
                    DescriptionItemNewRow(itemId: model.id, description: model.description, cacheItemListModel: cacheItemListModel)
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                        .lineLimit(3)
                }
            }
            .padding(.leading, isSpecialCategory ? 0 : 6)
            .frame(minHeight: 64, alignment: .center)
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
            if model.category != .folder && model.category != root.itemControllable.collectionCategory {
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
                if model.category != .folder && model.category != root.itemControllable.collectionCategory {
                    CategoryItemRow(category: model.category)
                }
                TagItemRow(tags: tagFirstContent)
            }
            
            HStack(spacing: 4) {
                TagItemRow(tags: tagSecondContent)
            }
        }
    }
    
    @ViewBuilder
    var actionBarWithSharing: some View {
        switch root.viewControllable.sharingViewType {
        case .none:
            actionBar
        case .share:
            actionBar
                .shareListItem(isActive: canShare, feedBackEnabled: true, action: shareAction)
        case .custom:
            root.viewControllable.sharingView(for: model.id)
        }
    }
    
    var canShare: Bool {
        if gameModus == .player {
            let features = sharingFeatureActions.features()
            switch root.module {
            case .photo:
                return features.photoSharing && showGame
            case .audio:
                return features.audioSharing && showGame
            case .space:
                return features.spaceSharing && showGame
            default:
                return false
            }
        } else {
            return showGame
        }
    }
    
    func shareAction() {
        Task {
            if gameModus == .master {
                await networkActions?.shareId(root.gameControllable.share(id: model.id))
            } else {
                if let result = try? await root.gameControllable.createGameData(for: model.id) {
                    networkActions?.game(result, .generic)
                }
            }
        }
    }
}

//#Preview("Split", traits: .mockData) {
//    @Previewable @Environment(FakeItemRootController.self) var root
//    
//    ItemRowView(root: root, model: ItemDataModel(), cacheItemListModel: CacheItemListModel())
//}

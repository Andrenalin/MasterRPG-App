// @copyright André Trettin

import SwiftUI

struct ListRowItemView: View {
    let root: any ItemRootControllable
    let item: FolderListItemModel
    let listController: any FolderListControllable
    let parentModel: (any ItemDataAccessable)?
    let menuController: ContextMenuMultiController
    let leadingPadding: CGFloat
    
    var body: some View {
        // Use the pre-resolved model from FolderListItemModel (set by mapResult via itemSync).
        // Falls back to itemOrEmpty only for items not yet through the search pipeline.
        let model = item.model ?? root.itemControllable.itemOrEmpty(for: item.source.itemId)
        HStack {
            ItemRowView(
                root: root,
                model: model,
                cacheItemListModel: listController.cacheListItemModel,
                listDisplayModel: listController.listDisplayModel,
                searchModel: listController.searchModel,
                isSelected: false
            ) {
                if root.viewControllable.thumbnailRowViewType == .custom {
                    root.viewControllable.thumbnailRowView(for: item.source.itemId)
                } else if root.viewControllable.thumbnailRowViewType == .photo,
                          let cacheController = root.cacheControllable {
                    ThumbnailRowPhotoView(
                        cacheController: cacheController,
                        model: model,
                        listDisplayModel: listController.listDisplayModel
                    )
                }
            }
            .draggable(for: root.configurable.module, itemId: item.source.itemId, entryId: nil, name: model.name)
            // Always-present contextMenu: empty closure = no menu when in selection mode
            .contextMenu {
                if !listController.listDisplayModel.isSelectionMode {
                    ListRootContextMenu(
                        root: root,
                        controller: menuController,
                        parentItem: parentModel,
                        currentSelected: item.source.itemId,
                        listController: listController
                    )
                }
            }
            
            SpecialCategoryFolderIndicator(
                item: item,
                listController: listController
            )
        }
        .environment(listController.listDisplayModel)
        .padding(.leading, CGFloat(item.level * 16))
        .dropDestination(for: root.configurable.module, isEnabled: parentModel != nil, handler: addLink)
        .listRowInsets(EdgeInsets(top: 2, leading: leadingPadding, bottom: 2, trailing: 0))
        .listRowSeparatorAll(item.isOpen ? .visible : .hidden, edges: .bottom)
    }
    
    private func addLink(name: String, itemId: UUID, entryId: UUID?) {
        guard let parentModel else { return }
        withAnimation {
            root.editControllable.addItem(itemId: itemId, parentId: parentModel.id)
            listController.scheduleDetailSearch()
            root.folderListControllable.resetFilter()
        }
    }
}

#Preview {
    let fixture = FakeItemRootControllerFixture()
    let item = {
        let item = FolderListItemModel(
            id: .fixture1,
            source: ItemRowModel(itemId: .fixture2, typeId: .none),
            destination: nil,
            level: 0,
            isShown: false
        )
        item.model = FakeItemModel(
            id: .fixture2,
            name: "Goblin Ambush",
            description: "A deterministic list row.",
            entries: []
        )
        return item
    }()
    ListRowItemView(
        root: fixture.root,
        item: item,
        listController: fixture.folderListController,
        parentModel: nil,
        menuController: ContextMenuMultiController(
            editController: fixture.editController,
            itemController: fixture.itemController,
            listModel: fixture.folderListController.listModel
        ),
        leadingPadding: 8
    )
}

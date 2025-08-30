// @copyright André Trettin

import CoreExternalRPG
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SubItemListRootView: View {
    let root: ItemRootControllable
    let listModel: ListModel
    let parentModel: ItemDataModel

    @Environment(CacheItemListModel.self) private var cacheItemListModel
    @Environment(\.navigator) private var navigator

    @Query(filter: #Predicate<ItemDataModel>{ $0.displayState == 0 }, sort: \ItemDataModel.name, animation: .smooth) private var items: [ItemDataModel]

    var body: some View {
        let _ = Self._printChanges()
        let _ = print(parentModel.name)
        
        listView
            .animation(.smooth, value: displayItems.count)
            .frame(minWidth: 250, idealWidth: 350)
#if !os(tvOS)
            .applyIf(listController.listDisplayModel.isSelectionMode) { content in
                content.contextMenu(forSelectionType: ListItemModel.ID.self) { selectedItemIDs in
                    ItemListContextMenu(controller: menuController)
                }
            }
#endif
            .scrollIndicatorsFlash(onAppear: true)
            .scrollIndicatorsFlash(trigger: displayItems.count)
#if !os(visionOS)
            .scrollDismissesKeyboard(.immediately)
#endif
            .overlay {
                if displayItems.isEmpty && !listController.searchModel.searchText.isEmpty {
                    ContentUnavailableView.search
                }
            }
            .onChange(of: items, initial: true) {
                withAnimation { root.listControllable.update(items: items.filter { $0.module == root.module }, parentModel: parentModel) }
            }
            .listModelUpdatesModifier(listControllable: root.listControllable, parentModel: parentModel)
            .toolbarItemListModifier(root: root, listControllable: root.listControllable, parentModel: parentModel)
    }
}

private extension SubItemListRootView {
    var listController: any ListControllable {
        root.listControllable
    }

    var displayItems: [ListItemModel] {
        listController.displayItems(for: parentModel)
    }
    
    var fileTypes: [UTType] {
        root.editControllable.fileUrlDataController?.fileTypes ?? []
    }
    
    var menuController: any ItemListContextMenuControllable {
        ContextMenuMultiController(editController: root.editControllable, itemController: root.itemControllable, listModel: listModel)
    }

    @ViewBuilder
    var listView: some View {
        ScrollViewReader { proxy in
            Group {
                @Bindable var listModel = listModel
#if os(macOS)
                if listController.listDisplayModel.isSelectionMode {
                    List(selection: $listModel.listSelection) {
                        itemRows()
                    }
                } else {
                    List(selection: $listModel.selected) {
                        itemRows()
                    }
                }
#else
                List(selection: $listModel.listSelection) {
                    itemRows()
                }
#endif
            }
            .onChange(of: listModel.scrollId) {
                guard let id = listModel.scrollId else { return }
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    func itemRows() -> some View {
        ForEach(displayItems) { item in
            HStack {
                ItemRowView(root: root, model: item.model, cacheItemListModel: cacheItemListModel, isSelected: false) {
                    if root.viewControllable.thumbnailRowViewType == .custom {
                        root.viewControllable.thumbnailRowView(for: item.model.id)
                    } else if root.viewControllable.thumbnailRowViewType == .photo, let cacheController = root.cacheControllable {
                        ThumbnailRowPhotoView(cacheController: cacheController, model: item.model)
                    }
                }
                .applyIf(!listController.listDisplayModel.isSelectionMode) { content in
                    content.contextMenu {
                        ItemListContextMenu(controller: menuController, currentSelected: item.model.id)
                    }
                }

                specialCategoryFolderIndicator(item: item)
            }
            .padding(.leading, CGFloat(item.level * 16))
#if !os(tvOS)
            .dropDestination(for: LinkData.self) { items, _ in
                addLinks(links: items)
            }
#endif
            .listRowInsets(EdgeInsets(top: 2, leading: leadingPadding, bottom: 2, trailing: 0))
            .listRowSeparator(item.isOpen ? .visible : .hidden, edges: .bottom)
        }
        .onDelete(perform: deleteItems)
        .onMove(perform: moveItems)
        .moveDisabled(parentModel.category == .folder)
        .deleteDisabled(root.listControllable.listDisplayModel.isSelectionMode)
    }

    func addLinks(links: [LinkData]) {
        links.forEach { link in
            guard link.module == root.module else { return }
            withAnimation { root.editControllable.addItem(itemId: link.itemId, in: parentModel, folderId: listModel.lastFolderId) }
        }
    }
    
    func deleteItems(offsets: IndexSet) {
        root.editControllable.removeItem(offsets: offsets, model: parentModel)
        listModel.deleteItems(offsets: offsets)
    }
    
    func moveItems(source: IndexSet, destination: Int) {
        root.editControllable.moveItems(source: source, destination: destination, model: parentModel)
    }

    var leadingPadding: CGFloat {
        let value = root.listControllable.listDisplayModel.isSelectionMode ? 12 : 8
        return CGFloat(valueFor(iOS: value, macOS: 4, tvOS: value, visionOS: value))
    }

    @ViewBuilder
    func specialCategoryFolderIndicator(item: ListItemModel) -> some View {
        if item.model.specialCategory {
            Image(systemName: item.isOpen ? "chevron.down" : "chevron.right")
                .imageScale(.small)
                .padding(.trailing)
                .foregroundStyle(item.isOpen ? Color.accentColor : Color.secondary)
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation { root.listControllable.toggleFolder(item: item, parentModel: parentModel) }
                }
        }
    }
}

//#Preview("Split", traits: .mockData) {
//    @Previewable @Environment(FakeItemRootController.self) var root
//    
//    ListRootView(root: root, parentModel: nil)
//}

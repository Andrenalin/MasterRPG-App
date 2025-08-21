// @copyright André Trettin

import CoreExternalRPG
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ListRootView: View {
    let root: ItemRootControllable
    let parentModel: ItemDataModel?

    @Environment(CacheItemListModel.self) private var cacheItemListModel

    @Environment(\.navigator) private var navigator

#if os(iOS) || os(visionOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var editMode: EditMode = .inactive
#endif

    @Query(filter: #Predicate<ItemDataModel>{ $0.displayState == 0 }, sort: \ItemDataModel.name, animation: .smooth) private var items: [ItemDataModel]

    var body: some View {
        listView
            .frame(minWidth: 250, idealWidth: 350)
            .overlay {
                if displayItems.isEmpty && !listController.searchModel.searchText.isEmpty {
                    ContentUnavailableView.search
                }
            }
            .toolbarItemListModifier(root: root, parentModel: parentModel)
            .animation(.smooth, value: displayItems.count)
#if os(iOS) || os(visionOS)
            .environment(\.editMode, $editMode)
#endif
            .scrollIndicatorsFlash(onAppear: true)
            .scrollIndicatorsFlash(trigger: displayItems.count)
#if !os(visionOS)
            .scrollDismissesKeyboard(.immediately)
#endif
            .applyIf(parentModel == nil) {
                $0.navigationTitle(root.module.title)
            }
            .onAppear {
                withAnimation { listModel.resetListModel() }
            }
            .onChange(of: listController.listDisplayModel.isSelectionMode) {
                listModel.update(selectionMode: listController.listDisplayModel.isSelectionMode)
            }
            .onChange(of: listModel.listSelection) {
                updateListSelection()
            }
            .onChange(of: listModel.selected) {
                updateSelected()
            }
            .onChange(of: listController.listDisplayModel.listMode) {
                withAnimation { listController.resetFilter() }
            }
#if os(iOS) || os(visionOS)
            .onChange(of: listController.listDisplayModel.isSelectionMode) {
                editMode = listController.listDisplayModel.isSelectionMode ? .active : .inactive
            }
#endif
            .onChange(of: items, initial: true) {
                withAnimation { root.listControllable.update(items: items) }
            }
//#if !os(tvOS)
//        .onDrop(of: [.fileURL], delegate: FileDropDelegate(for: FileController.fileTypes, updateFile: updateFile))
//#endif
    }
}

//private extension ListRootView {
//    var menuController: any ItemListContextMenuControllable {
//        ContextMenuMultiController(editController: root.editControllable, itemController: root.itemControllable, listModel: root.listControllable.listModel)
//    }
//    
//    func updateFile(url: URL) {
//        Task { @MainActor in
//            let model = root.editControllable.addNew(modelContext: modelContext, type: .item)
//            try? await Task.sleep(for: .seconds(0.5))
//            withAnimation {
//                root.editControllable.resetFile(url: url, in: model)
//                root.listControllable.listModel.set(selectedItemId: model.id)
//            }
//        }
//    }
//}

private extension ListRootView {
    var listController: any ListControllable {
        root.listControllable
    }

    var displayItems: [ListItemModel] {
        listController.displayItems(for: parentModel)
    }

    var listModel: ListModel {
        listController.listModel(for: parentModel)
    }

    func updateListSelection() {
        listModel.update(selection: listModel.listSelection)
    }

    func updateSelected() {
        if let id = listModel.selected, let item = displayItems.first(where: { $0.id == id }) {

//            if item.model.id == EditController.Model.dropItem.id {
//                navigator.navigate(to: route(EditController.Model.dropItem.id), method: .sheet)
//                listModel.update(selection: [])
//            } else {
                listModel.listSelection <=> Set(arrayLiteral: id)
            navigator.navigate(to: ItemRootRoute.detail(item.model.id), method: .push)
  //          }
        } else {
            listModel.resetListSelection()
        }
    }

    @ViewBuilder
    var listView: some View {
        @Bindable var listModel = listModel
#if os(macOS)
        if root.listController.listDisplayModel.isSelectionMode {
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

    func itemRows() -> some View {
        ForEach(displayItems) { item in
            HStack {
                ItemRowView(root: root, model: item.model, cacheItemListModel: cacheItemListModel, isSelected: false)
#if !os(tvOS)
                    .draggable(LinkData(itemId: item.model.id, module: root.module, name: item.model.name))
#endif
                    .applyIf(!root.listControllable.listDisplayModel.isSelectionMode) { content in
                        content.contextMenu {
//                            ItemListContextMenu(controller: menuController, currentSelected: item.itemId)
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
//        .onDelete(perform: deleteItems)
//        .onMove(perform: moveItems)
        .moveDisabled(parentModel == nil || parentModel?.category == .folder)
        .deleteDisabled(root.listControllable.listDisplayModel.isSelectionMode)
    }

    func addLinks(links: [LinkData]) {
        guard let parentModel else { return }
        links.forEach { link in
            guard link.module == root.module else { return }
            withAnimation { root.editControllable.addItem(itemId: link.itemId, in: parentModel, folderId: listModel.lastFolderId) }
        }
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
                    withAnimation { root.listControllable.toggleFolder(item: item) }
                }
        }
    }
}

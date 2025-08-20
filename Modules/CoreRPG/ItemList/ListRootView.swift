// @copyright André Trettin

import CoreExternalRPG
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ListRootView: View {
    let root: ItemRootControllable
    let parentModel: ItemDataModel?

    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<ItemDataModel>{ $0.displayState == 0 }, sort: \ItemDataModel.name, animation: .smooth) private var items: [ItemDataModel]

    var body: some View {
        listView()
//        ItemListView(listController: root.listControllable, editController: root.editControllable, menuController: menuController, parentModel: nil, module: root.module) { id in
//            ItemRootRoute.detail(id)
//        } row: { itemId in
//            if let model = root.itemControllable.modelSync(for: itemId) {
//                //MainRowView(model: model)
//            }
//        }
        .onChange(of: items, initial: true) {
//            withAnimation { root.listControllable.update(items: items) }
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
    var displayItems: [ListItemModel] {
        root.listControllable.displayItems(for: parentModel)
    }

    var listModel: ListModel {
        root.listControllable.listModel(for: parentModel)
    }

    func updateListSelection() {
        listModel.update(selection: listModel.listSelection)
    }

    @ViewBuilder
    func listView() -> some View {
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
                Text(item.model.name)
                //row(item.model.id)
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

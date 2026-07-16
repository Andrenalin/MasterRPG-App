// @copyright André Trettin

import SwiftUI

struct ItemRowsView: View {
    let root: any ItemRootControllable
    let listController: any FolderListControllable
    let parentModel: (any ItemDataAccessable)?
    let listModel: FolderListModel
    let menuController: ContextMenuMultiController
    
    @Environment(\.navigator) private var navigator
    
    var body: some View {
        if listModel.list.isEmpty && parentModel != nil {
            dropHereView
        }
        
        ForEach(listModel.list) { item in
            ListRowItemView(
                root: root,
                item: item,
                listController: listController,
                parentModel: parentModel,
                menuController: menuController,
                leadingPadding: leadingPadding
            )
        }
        .onDelete(perform: deleteItems)
        .onMove(perform: moveItems)
        .moveDisabled(parentModel == nil || parentModel?.category == .folder)
        .deleteDisabled(listController.listDisplayModel.isSelectionMode)
    }
    
    private var dropHereView: some View {
        VStack(spacing: 0) {
            Text("Drop here", bundle: .module)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
                .background(root.configurable.module.color.gradient, in: .capsule)
                .padding()
                .dropDestination(for: root.configurable.module, isEnabled: true, handler: addLink)
            
            Text("Drag items from the list or the inspector on this drop field to add the item to the folder or collection. After the first item is added you can add more items by dropping it on the exisiting items in this detail list.", bundle: .module)
                .padding()
                .lineLimit(5)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
    
    private func addLink(name: String, itemId: UUID, entryId: UUID?) {
        guard let parentModel else { return }
        withAnimation {
            root.editControllable.addItem(itemId: itemId, parentId: parentModel.id)
            listController.scheduleDetailSearch()
            root.folderListControllable.resetFilter()
        }
    }
    
    private func deleteItems(offsets: IndexSet) {
        if let parentModel {
            root.editControllable.removeItem(offsets: offsets, itemId: parentModel.id)
            listModel.deleteItems(offsets: offsets)
        } else {
            let removingItems = listController.delete(offsets: offsets)
            guard !removingItems.isEmpty else { return }
            root.removeEntryListModel.removeItems = root.editControllable.markCollectionItemsForRemoval(for: removingItems)
            navigator.navigate(to: InternalRoute.removeAlert, method: .managedSheet)
        }
    }
    
    private func moveItems(source: IndexSet, destination: Int) {
        guard let parentModel else { return }
        root.editControllable.moveItems(source: source, destination: destination, itemId: parentModel.id)
    }
    
    private var leadingPadding: CGFloat {
        let value = listController.listDisplayModel.isSelectionMode ? 12 : 8
        return CGFloat(valueFor(iOS: value, macOS: 4, tvOS: value, visionOS: value))
    }
}

#Preview("Item Rows") {
    let fixture = FakeItemRootControllerFixture()
    ItemRowsView(
        root: fixture.root,
        listController: fixture.folderListController,
        parentModel: nil,
        listModel: fixture.folderListController.listModel,
        menuController: ContextMenuMultiController(
            editController: fixture.editController,
            itemController: fixture.itemController,
            listModel: fixture.folderListController.listModel
        )
    )
}

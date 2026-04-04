// @copyright André Trettin

import SwiftUI

extension View {
    func listModelUpdatesModifier(listControllable: any FolderListControllable, itemControllable: any ItemControllable) -> some View {
        modifier(ListModelUpdatesViewModifier(listControllable: listControllable, itemControllable: itemControllable))
    }
}

struct ListModelUpdatesViewModifier: ViewModifier {
    let listControllable: any FolderListControllable
    let itemControllable: any ItemControllable
    
    @Environment(\.navigator) private var navigator
    
#if os(iOS) || os(visionOS)
    @State private var editMode: EditMode = .inactive
#endif
    
    func body(content: Content) -> some View {
        content
#if os(iOS) || os(visionOS)
            .environment(\.editMode, $editMode)
#endif
            .onChange(of: listModel.listSelection) {
                withAnimation {  updateListSelection() }
            }
            .onChange(of: listModel.selected) {
                withAnimation { updateSelected() }
            }
            .onChange(of: listControllable.listDisplayModel.listMode, initial: true) {
                withAnimation { listControllable.resetFilter() }
            }
            .onChange(of: listControllable.listDisplayModel.isSelectionMode) {
                withAnimation { listModel.update(selectionMode: listControllable.listDisplayModel.isSelectionMode) }
#if os(iOS) || os(visionOS)
                withAnimation { editMode = listControllable.listDisplayModel.isSelectionMode ? .active : .inactive }
#endif
            }
            .task {
                await updateStreamChanges()
            }
    }
}

private extension ListModelUpdatesViewModifier {
    func updateStreamChanges() async {
        let stream = Observations {
            if let parentModel = listModel.parentModel {
                parentModel.entries.map(\.childId)
            } else {
                itemControllable.itemDataModel.items
            }
        }

        for await itemIds in stream {
            var updatedItems: [any ItemDataAccessable] = []
            for item in itemIds {
                guard let item = await itemControllable.item(for: item), item.displayState != 2 else { continue }
                updatedItems.append(item)
            }
            listControllable.update()
        }
    }
    
    var listModel: FolderListModel {
        listControllable.listModel
    }

    var displayItems: [ListItemModel] {
        listControllable.displayItems
    }

    func updateListSelection() {
        listModel.update(selection: listModel.listSelection)
    }

    func updateSelected() {
        if let id = listModel.selected {
            listModel.listSelection <=> Set(arrayLiteral: id)
            if let itemId = listModel.selectedItemId {
                if listModel.parentModel != nil {
                    listModel.subFolderRoute = itemId
//                    if listModel.navigationModel.folderItems.last != itemId {
//                        let oldFolderItem = listModel.navigationModel.folderItems
//                        listModel.navigationModel.folderItems.append(itemId)
//                        print("**** \(oldFolderItem) vs. \(listModel.navigationModel.folderItems)")
//                    }
                } else {
                    listModel.itemRoute = itemId
                    listModel.navigationModel.selectedItemId = itemId
                }
            }
        } else {
            listModel.resetListSelection()
        }
        
    }
}

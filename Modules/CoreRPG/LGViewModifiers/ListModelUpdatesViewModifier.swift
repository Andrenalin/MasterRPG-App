// @copyright André Trettin

import SwiftUI

extension View {
    func listModelUpdatesModifier(
        listControllable: any FolderListControllable,
        itemControllable: any ItemControllable,
        parentModel: (any ItemDataAccessable)? = nil
    ) -> some View {
        modifier(ListModelUpdatesViewModifier(
            listControllable: listControllable,
            itemControllable: itemControllable,
            parentModel: parentModel
        ))
    }
}

struct ListModelUpdatesViewModifier: ViewModifier {
    let listControllable: any FolderListControllable
    let itemControllable: any ItemControllable
    /// When set, the modifier is operating in detail-list context (folder/collection content).
    let parentModel: (any ItemDataAccessable)?

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
                // Route through the single search pipeline; detail context when a parent scope is active.
                if parentModel != nil {
                    listControllable.scheduleDetailSearch()
                } else {
                    listControllable.scheduleSearch()
                }
            }
            .onChange(of: listControllable.listDisplayModel.isSelectionMode, initial: true) {
                withAnimation {
                    listModel.update(selectionMode: listControllable.listDisplayModel.isSelectionMode)
#if os(iOS) || os(visionOS)
                    editMode = listControllable.listDisplayModel.isSelectionMode ? .active : .inactive
#endif
                }
            }
            .task {
                await updateStreamChanges()
            }
    }
}

private extension ListModelUpdatesViewModifier {
    func updateStreamChanges() async {
        let stream = Observations {
            if let parentModel {
                // Detail context: watch the folder/collection's own entries for add/remove changes.
                parentModel.entries.map(\.childId)
            } else {
                itemControllable.itemDataModel.items
            }
        }

        for await _ in stream {
            listControllable.update()
        }
    }

    /// In detail context the modifier operates on `detailListModel` so that
    /// selection, scroll, and edit-mode changes apply to the folder's child list.
    var listModel: FolderListModel {
        if parentModel != nil, let detail = listControllable.listModel.detailListModel {
            return detail
        }
        return listControllable.listModel
    }

    func updateListSelection() {
        listModel.update(selection: listModel.listSelection)
    }

    func updateSelected() {
        if let id = listModel.selected {
            listModel.listSelection <=> Set(arrayLiteral: id)
            if let itemId = listModel.selectedItemId {
                if listModel.parentModel != nil {
                    if let navigator = listModel.navigationModel.navigator?.currentNavigator {
                        navigator.navigate(to: listControllable.folderDestination(for: itemId))
                    }
                    listModel.selected = nil
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

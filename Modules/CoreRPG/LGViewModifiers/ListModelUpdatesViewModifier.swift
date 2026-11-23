// @copyright André Trettin

import SwiftUI

extension View {
    func listModelUpdatesModifier(
        listControllable: any FolderListControllable,
        itemControllable: any ItemControllable,
        parentModel: (any ItemDataAccessible)? = nil
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
    let parentModel: (any ItemDataAccessible)?

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
            // Keyed on the observed folder: a reused detail view that switches to another folder
            // must watch that folder's entries, not the first one's. See CODE_AUDIT §5.18.
            .task(id: parentModel?.id) {
                await updateStreamChanges()
            }
    }
}

private extension ListModelUpdatesViewModifier {
    func updateStreamChanges() async {
        let stream = Observations {
            if let parentModel {
                // Detail context: watch the folder/collection's own entries for add/remove changes,
                // and the entries of its group items, which the inspector lists under the group
                // entry (an entry moved between groups changes neither of the parent's own entries).
                parentModel.entries.map(\.childId)
                    + parentModel.entries.compactMap { ($0 as? any GroupableEntry)?.groupItemId }
                        .flatMap { itemControllable.itemSync(for: $0)?.entries.map(\.id) ?? [] }
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
        guard let id = listModel.selected else {
            listModel.resetListSelection()
            return
        }
        if let itemId = listModel.takeDetailSelection() {
#if os(macOS)
            listModel.subFolderRoute = itemId
#else
            // The stack showing this list: the list's own stack on iPhone, the split's detail
            // stack on iPad. `currentNavigator` is the stack that appeared last, which on iPad
            // can be the list column.
            navigator.navigate(to: listControllable.folderDestination(for: itemId))
#endif
            return
        }
        listModel.listSelection <=> Set(arrayLiteral: id)
        if let itemId = listModel.selectedItemId {
            listModel.itemRoute = itemId
            listModel.navigationModel.selectedItemId = itemId
        }
    }
}

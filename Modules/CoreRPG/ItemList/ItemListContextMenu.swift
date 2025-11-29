// @copyright André Trettin

import SwiftUI

struct ItemListContextMenu: View {
    let listController: any ListControllable
    let selection: Set<ItemRowTreeModel>
    let exportDisabled: Bool
    let generatorDisabled: Bool
    let removeEntryList: RemoveEntryListModel?
    @Binding var showEditGroup: Bool
    @Binding var showExport: Bool

    var body: some View {
#if os(iOS) || os(visionOS)
        selectItemView
#endif
        createLinkItemsView(selection: selection)
        copyItemsView(selection: selection)
        groupEditItemsView(selection: selection)
        
        if !generatorDisabled {
            generatorItemsView(selection: selection)
        }
        if !exportDisabled {
            exportItemsView(selection: selection)
        }
        focusItemsView(selection: selection)
        
        if listController.canGroup {
            groupItemsView(selection: selection)
        }
        deleteItemsView(selection: selection)
    }
}

private extension ItemListContextMenu {
    func copyItemsView(selection: Set<ItemRowTreeModel>) -> some View {
        Button {
            Task {
                await listController.copyItems(selection: selection)
            }
        } label: {
            Label { Text(listController.copyTitle(for: selection), bundle: .module) } icon: { Image(systemName: "doc.on.doc") }
        }
        .disabled(listController.selectionCount(for: selection, filterEntries: true) == 0)
    }
    
    func createLinkItemsView(selection: Set<ItemRowTreeModel>) -> some View {
        Button {
            Task {
                await listController.createLinks(selection: selection)
            }
        } label: {
            Label { Text(listController.createLinkTitle(for: selection), bundle: .module) } icon: { Image(systemName: "link") }
        }
    }

    @ViewBuilder
    func deleteItemsView(selection: Set<ItemRowTreeModel>) -> some View {
        if let removeEntryList {
            Button(role: .destructive) {
                withAnimation { listController.resetAction(selection: selection) }
                removeEntryList.removeItems = listController.model.actionSelection.map { $0.model }
                withAnimation { removeEntryList.showDeleteAlert.toggle() }
            } label: {
                Label { Text(listController.deleteTitle(for: selection), bundle: .module) } icon: { Image(systemName: "trash") }
            }
            .disabled(listController.selectionCount(for: selection, filterEntries: true) == 0)
        }
    }
    
    func exportItemsView(selection: Set<ItemRowTreeModel>) -> some View {
        Button {
            withAnimation { listController.resetAction(selection: selection) }
            withAnimation { showExport.toggle() }
        } label: {
            Label { Text(listController.exportTitle(for: selection), bundle: .module) } icon: { Image(systemName: "square.and.arrow.up") }
        }
        .disabled(listController.selectionCount(for: selection, filterEntries: true) == 0)
    }
    
    func focusItemsView(selection: Set<ItemRowTreeModel>) -> some View {
        Button {
            Task { await listController.focus(for: selection) }
        } label: {
            Label { Text(listController.focusTitle(for: selection), bundle: .module) } icon: { Image(systemName: "camera.viewfinder") }
        }
        .disabled(selection.filter { $0.model.entryId == nil }.isEmpty)
    }
    
    func generatorItemsView(selection: Set<ItemRowTreeModel>) -> some View {
        Button {
            withAnimation { listController.model.showGeneratorItem = listController.selected(for: selection)?.model }
        } label: {
            Label { Text(listController.generateTitle(for: selection), bundle: .module) } icon: { Image(systemName: "gear") }
        }
    }

    func groupItemsView(selection: Set<ItemRowTreeModel>) -> some View {
        Button {
            withAnimation { listController.groupItems(for: selection) }
        } label: {
            Label { Text(listController.groupTitle(for: selection), bundle: .module) } icon: { Image(systemName: "square.on.square.squareshape.controlhandles") }
        }
        .disabled(listController.isGroupDisabled(for: selection))
    }

    func groupEditItemsView(selection: Set<ItemRowTreeModel>) -> some View {
        Button {
            withAnimation { listController.resetAction(selection: selection) }
            withAnimation { showEditGroup.toggle() }
        } label: {
            Label { Text(listController.groupEditTitle(for: selection), bundle: .module) } icon: { Image(systemName: "slider.horizontal.2.square.on.square") }
        }
        .disabled(selection.filter { $0.model.entryId == nil }.count < 2)
    }

    var selectItemView: some View {
        Button {
            withAnimation { listController.model.selectedItems = listController.model.selectedItems.isEmpty ? listController.model.filteredItems : [] }
        } label: {
            if listController.model.selectedItems.isEmpty {
                Label { Text("Select", bundle: .module) } icon: { Image(systemName: "checkmark.circle.fill") }
            } else {
                Label { Text("Deselect", bundle: .module) } icon: { Image(systemName: "checkmark.circle") }
            }
        }
    }
}

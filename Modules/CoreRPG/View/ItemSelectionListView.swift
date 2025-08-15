// @copyright André Trettin

import CoreExternalRPG
import SwiftData
import SwiftUI

public struct ItemSelectionListView<EditController: EditControllable, Row: View>: View where EditController.Model.ID == UUID {
    public init(editController: EditController, items: [EditController.Model], module: NetworkModules, route: @escaping (UUID) -> any NavigationDestination, @ViewBuilder row: @escaping (UUID) -> Row) {
        self.editController = editController
        self.items = items
        self.module = module
        self.route = route
        self.row = row
    }
    let editController: EditController
    let items: [EditController.Model]
    let module: NetworkModules
    let route: (UUID) -> any NavigationDestination
    let row: (UUID) -> Row
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.navigator) private var navigator

    @Environment(CacheItemListModel.self) private var cacheItemListModel
    @Environment(ListModel.self) private var listModel
    @Environment(ListDisplayModel.self) private var listDisplayModel
    @Environment(SearchModel.self) private var searchModel

#if os(iOS) || os(visionOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    
    public var body: some View {
        listView(filteredItems: totalItems(items: items))
            .frame(minWidth: 250, idealWidth: 350)
            .overlay {
                if items.isEmpty && !searchModel.searchText.isEmpty {
                    ContentUnavailableView.search
                }
            }
            .animation(.smooth, value: items.count)
            .scrollIndicatorsFlash(onAppear: true)
            .scrollIndicatorsFlash(trigger: items.count)
#if !os(visionOS)
            .scrollDismissesKeyboard(.immediately)
#endif
            .navigationTitle(module.title)
            .onAppear {
                listModel.resetListModel()
            }
            .onChange(of: listModel.listSelection) {
                guard !listModel.listSelection.isEmpty else { return }
                listModel.update(selection: listModel.listSelection)
            }
            .onChange(of: listModel.selected) {
                if let id = listModel.selected {
                    listModel.listSelection <=> Set(arrayLiteral: id)
                    let local = totalItems(items: items)
                    guard let modelId = local.first(where: { $0.id == id })?.model.id else { return }
                    navigator.navigate(to: route(modelId), method: .push)
                } else {
                    listModel.resetListSelection()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                }
                ToolbarItemGroup(placement: secondaryMenuPlacement) {
                    secondaryActionMenu
                }
            }
    }
}

private extension ItemSelectionListView {
    @ViewBuilder
    var secondaryActionMenu: some View {
        ControlGroup {
            CompactDisplayModeToggle(listDisplayModel: listDisplayModel)
            MediumDisplayModeToggle(listDisplayModel: listDisplayModel)
            RegularDisplayModeToggle(listDisplayModel: listDisplayModel)
        }
        ControlGroup {
            ListModeToggle(listDisplayModel: listDisplayModel)
            FolderModeToggle(listDisplayModel: listDisplayModel)
        }
    }
        
    func filteredItems(items: [EditController.Model], withParentFilter: Bool = true) -> [EditController.Model] {
        var filtered = items
        if withParentFilter {
            if listDisplayModel.listMode == .list {
                filtered = filtered.filter { $0.category != .folder && $0.category != EditController.Model.collectionCategory }
            } else {
                filtered = filtered.filter { $0.parentId == listModel.selectedParentId }
            }
        }
        if !searchModel.selectedTokens.isEmpty {
            let selectedTags = searchModel.selectedTokens.map { $0.tag }
            filtered = filtered.filter { $0.tags.contains(selectedTags) }
        }
        guard !searchModel.searchText.isEmpty else { return filtered }
        return filtered.filter {
            $0.name.localizedStandardContains(searchModel.searchText) ||
            $0.information.localizedStandardContains(searchModel.searchText)
        }
    }

    @ViewBuilder
    func listView(filteredItems: [ItemListModel<EditController.Model>]) -> some View {
        @Bindable var listModel = listModel
        List(selection: $listModel.listSelection) {
            itemRows(filteredItems: filteredItems)
        }
    }
    
    func itemRows(filteredItems: [ItemListModel<EditController.Model>]) -> some View {
        ForEach(filteredItems) { item in
            row(item.model.id)
                .selectListItem {
                    if listModel.selection.contains(item.id) {
                        listModel.selection.removeAll { $0 == item.id }
                    } else {
                        listModel.selection.append(item.id)
                    }
                } isSelected: {
                    listModel.selection.contains(item.id)
                }
                .padding(.leading, CGFloat(item.level * 16))
                .listRowInsets(EdgeInsets(top: 2, leading: leadingPadding, bottom: 2, trailing: 0))
                .listRowSeparator(item.isOpen ? .visible : .hidden, edges: .bottom)
        }
    }
    
    var leadingPadding: CGFloat {
        CGFloat(valueFor(iOS: 8, macOS: 4, tvOS: 8, visionOS: 8))
    }
    
    func totalItems(items: [EditController.Model], level: Int = 0, withParentFilter: Bool = true, entryIds: [UUID: UUID] = [:]) -> [ItemListModel<EditController.Model>] {
        var total: [ItemListModel<EditController.Model>] = []
        guard level < 10 else { return total }
        filteredItems(items: items, withParentFilter: withParentFilter).forEach { item in
            total.append(ItemListModel(id: entryIds[item.id, default: item.id], model: item, isOpen: listModel.isFolderOpen(itemId: item.id), level: level))
            if item.specialCategory && listModel.isFolderOpen(itemId: item.id) {
                let (newItems, newEntryIds) = item.subItems
                total.append(contentsOf: totalItems(items: newItems, level: level + 1, withParentFilter: false, entryIds: newEntryIds))
            }
        }
        return total
    }

    var secondaryMenuPlacement: ToolbarItemPlacement {
#if os(tvOS)
        .automatic
#else
        .secondaryAction
#endif
    }
}

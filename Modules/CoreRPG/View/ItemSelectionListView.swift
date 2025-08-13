// @copyright André Trettin

import CoreExternalRPG
import SwiftData
import SwiftUI

public struct ItemSelectionListView<EditController: EditControllable, Row: View>: View where EditController.Model.ID == UUID {
    public init(editController: EditController, items: [EditController.Model], module: NetworkModules, route: @escaping (UUID) -> any NavigationDestination, @ViewBuilder row: @escaping (EditController.Model) -> Row) {
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
    let row: (EditController.Model) -> Row
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @Environment(CacheItemListModel.self) private var cacheItemListModel
    @Environment(SearchModel.self) private var searchModel

    @State private var listModel = ListModel()

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
            .onChange(of: listModel.listSelection) {
                guard !listModel.listSelection.isEmpty else { return }
                listModel.update(selection: listModel.listSelection)
            }
            .onChange(of: listModel.selected) {
                if let id = listModel.selected {
                    listModel.listSelection <=> Set(arrayLiteral: id)
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
            CompactDisplayModeToggle(listModel: listModel)
            MediumDisplayModeToggle(listModel: listModel)
            RegularDisplayModeToggle(listModel: listModel)
        }
        ControlGroup {
            ListModeToggle(listModel: listModel)
            FolderModeToggle(listModel: listModel)
        }
    }
        
    var filteredItems: [EditController.Model] {
        var filtered = items
        if listModel.listMode == .list {
            filtered = filtered.filter { $0.category != .folder && $0.category != EditController.Model.collectionCategory }
        } else {
            filtered = filtered.filter { $0.parentId == listModel.selectedParentId }
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
    func listView(filteredItems: [EditController.Model]) -> some View {
        @Bindable var listModel = listModel
        List(selection: $listModel.listSelection) {
            itemRows(filteredItems: filteredItems)
        }
    }
    
    func itemRows(filteredItems: [EditController.Model]) -> some View {
        ForEach(filteredItems) { item in
            row(item)
                .selectListItem {
                    if listModel.selection.contains(item.id) {
                        listModel.selection.removeAll { $0 == item.id }
                    } else {
                        listModel.selection.append(item.id)
                    }
                } isSelected: {
                    listModel.selection.contains(item.id)
                }
                .listRowInsets(EdgeInsets(top: 2, leading: leadingPadding, bottom: 2, trailing: 0))
        }
    }
    
    var leadingPadding: CGFloat {
        let value = listModel.isSelectionMode ? 12 : 8
        return CGFloat(valueFor(iOS: value, macOS: 4, tvOS: value, visionOS: value))
    }
    
    func totalItems(items: [EditController.Model]) -> [EditController.Model] {
        var total: [EditController.Model] = []
        filteredItems.forEach { item in
            total.append(item)
            if item.isFolder && listModel.subItemModels[item.id]?.isOpen ?? false {
                total.append(contentsOf: totalItems(items: item.subItems))
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

// @copyright André Trettin

import CoreExternalRPG
import SwiftData
import SwiftUI

public struct LinkItemListView<ListController: ListControllable, Row: View>: View where ListController.Model.ID == UUID {
    public init(listController: ListController, parentModel: ListController.Model?, isInspector: Bool, @ViewBuilder row: @escaping (UUID) -> Row) {
        self.listController = listController
        self.parentModel = parentModel
        self.isInspector = isInspector
        self.row = row
        listController.listDisplayModel.listMode = parentModel?.category == .folder ? .folder : .list
    }

    let listController: ListController
    let parentModel: ListController.Model?
    let isInspector: Bool
    let row: (UUID) -> Row
    
    @Environment(ListDisplayModel.self) private var listDisplayModel
    
    public var body: some View {
        NavigationStack {
            @Bindable var searchModel = listController.searchModel
            @Bindable var inspectorDisplayModel = listController.listDisplayModel
            
            if isInspector {
                Picker(selection: $inspectorDisplayModel.listMode) {
                    ForEach(ListDisplayModel.ListMode.allCases) { mode in
                        Text(mode.title)
                            .tag(mode)
                    }
                } label: {
                    Text("List Mode")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .onChange(of: inspectorDisplayModel.listMode) {
                    withAnimation { listController.resetFilter() }
                }
                
                TextField("Filter", text: $searchModel.searchText)
                    .padding(.horizontal)
            }
                        
            contentView
                .onChange(of: listDisplayModel.displayMode, initial: true) {
                    inspectorDisplayModel.displayMode = listDisplayModel.displayMode
                    withAnimation { listController.resetFilter() }
                }
                .onChange(of: listController.searchModel.searchText) {
                    withAnimation { listController.resetFilter() }
                }
                .applyIf(!isInspector) { content in
                    content
                        .toolbar {
                            ToolbarItem(placement: .secondaryAction) {
                                ControlGroup {
                                    ListModeToggle(listDisplayModel: inspectorDisplayModel)
                                    FolderModeToggle(listDisplayModel: inspectorDisplayModel)
                                }
                            }
                        }
                        .searchable(text: $searchModel.searchText, placement: .automatic)
                        .navigationTitle(ListController.Model.typeId.title)
                }
        }
        .environment(listController.listDisplayModel)
        .environment(listController.listModel)
        .environment(listController.searchModel)
    }

    var contentView: some View {
        listView
            .frame(minWidth: 150, idealWidth: 250)
            .overlay {
                if listController.listModel.displayedItems.isEmpty && !listController.searchModel.searchText.isEmpty {
                    ContentUnavailableView.search
                }
            }
            .animation(.smooth, value: listController.listModel.displayedItems.count)
        #if os(macOS)
            //.listStyle(.inset(alternatesRowBackgrounds: true))
            .listStyle(.sidebar)
        #endif
            .scrollIndicatorsFlash(onAppear: true)
            .scrollIndicatorsFlash(trigger: listController.listModel.displayedItems.count)
            .scrollEdgeEffectStyle(.hard, for: .top)
#if !os(visionOS)
            .scrollDismissesKeyboard(.immediately)
#endif
    }
}

private extension LinkItemListView {
//    var totalItems: [ItemListModel<Model>] {
//        expandedItems(items: items)
//    }
//    
//    func filteredItems(items: [Model], withParentFilter: Bool = true) -> [Model] {
//        var filtered = items
//        if withParentFilter {
//            if inspectorDisplayModel.listMode == .folder {
//                filtered = items.filter { $0.parentId == nil }
//            } else {
//                filtered = items.filter { $0.category != .folder && $0.category != Model.collectionCategory }
//            }
//        }
//        if !searchModel.selectedTokens.isEmpty {
//            let selectedTags = searchModel.selectedTokens.map { $0.tag }
//            filtered = filtered.filter { $0.tags.contains(selectedTags) }
//        }
//        guard !searchModel.searchText.isEmpty else { return filtered }
//        return filtered.filter {
//            $0.name.localizedStandardContains(searchModel.searchText) ||
//            $0.information.localizedStandardContains(searchModel.searchText)
//        }
//    }
//    
//    func expandedItems(items: [Model], level: Int = 0, withParentFilter: Bool = true, entryIds: [UUID: UUID] = [:]) -> [ItemListModel<Model>] {
//        var total: [ItemListModel<Model>] = []
//        guard level < 10 else { return total }
//        let filtered = filteredItems(items: items, withParentFilter: withParentFilter)
//        filtered.forEach { item in
//            total.append(ItemListModel(id: entryIds[item.id, default: item.id], model: item, isOpen: listModel.isFolderOpen(itemId: item.id), level: level))
//            if item.specialCategory && listModel.isFolderOpen(itemId: item.id) {
//                let (newItems, newEntryIds) = item.subItems
//                total.append(contentsOf: expandedItems(items: newItems, level: level + 1, withParentFilter: false, entryIds: newEntryIds))
//            }
//        }
//        return total
//    }
    
    @ViewBuilder
    var listView: some View {
        @Bindable var listModel = listController.listModel
        List(selection: $listModel.listSelection) {
            itemRows()
        }
    }
    
    func itemRows() -> some View {
        ForEach(listController.listModel.displayedItems) { item in
            HStack {
                row(item.itemId)
                
                specialCategoryFolderIndicator(item: item)
            }
            .padding(.leading, CGFloat(item.level * 16))
            .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 0))
            .listRowSeparator(item.isOpen ? .visible : .hidden, edges: .bottom)

        }
    }
    
    var leadingPadding: CGFloat {
        CGFloat(valueFor(iOS: 8, macOS: 4, tvOS: 8, visionOS: 8))
    }
    
    @ViewBuilder
    func specialCategoryFolderIndicator(item: ListItemModel) -> some View {
        if item.isSpecial {
            Image(systemName: item.isOpen ? "chevron.down" : "chevron.right")
                .imageScale(.small)
                .padding(.trailing)
                .foregroundStyle(item.isOpen ? Color.accentColor : Color.secondary)
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation { listController.listModel.toggleFolder(itemId: item.itemId) }
                }
        }
    }
}

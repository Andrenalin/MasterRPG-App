// @copyright André Trettin

import CoreExternalRPG
import SwiftData
import SwiftUI

public struct LinkItemListView<Model: ItemDataAccessable, Row: View>: View where Model: ListItemFolderable, Model: Identifiable, Model.ID == UUID {
    public init(items: [Model], parentModel: Model?, isInspector: Bool, @ViewBuilder row: @escaping (UUID) -> Row) {
        self.items = items
        self.parentModel = parentModel
        self.isInspector = isInspector
        self.row = row
        let listDisplayModel = ListDisplayModel()
        listDisplayModel.listMode = parentModel?.category == .folder ? .folder : .list
        self._inspectorDisplayModel = State(wrappedValue: listDisplayModel)
    }

    let items: [Model]
    let parentModel: Model?
    let isInspector: Bool
    let row: (UUID) -> Row
    
    @Environment(ListDisplayModel.self) private var listDisplayModel
    @Environment(SearchModel.self) private var searchModel
    
    @State private var listModel = ListModel()
    @State private var inspectorDisplayModel = ListDisplayModel()
    
    public var body: some View {
        NavigationStack {
            @Bindable var searchModel = searchModel
            @Bindable var inspectorDisplayModel = inspectorDisplayModel
            
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
                
                TextField("Filter", text: $searchModel.searchText)
                    .padding(.horizontal)
            }
                        
            contentView
                .onChange(of: listDisplayModel.displayMode, initial: true) {
                    inspectorDisplayModel.displayMode = listDisplayModel.displayMode
                }
                .environment(inspectorDisplayModel)
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
                        .navigationTitle(Model.typeId.title)
                        
                }
        }
    }

    var contentView: some View {
        listView
            .frame(minWidth: 150, idealWidth: 250)
            .overlay {
                if totalItems.isEmpty && !searchModel.searchText.isEmpty {
                    ContentUnavailableView.search
                }
            }
            .animation(.smooth, value: totalItems.count)
            .environment(listModel)
        #if os(macOS)
            //.listStyle(.inset(alternatesRowBackgrounds: true))
            .listStyle(.sidebar)
        #endif
            .scrollIndicatorsFlash(onAppear: true)
            .scrollIndicatorsFlash(trigger: totalItems.count)
            .scrollEdgeEffectStyle(.hard, for: .top)
#if !os(visionOS)
            .scrollDismissesKeyboard(.immediately)
#endif
    }
}

private extension LinkItemListView {
    var totalItems: [ItemListModel<Model>] {
        expandedItems(items: items)
    }
    
    func filteredItems(items: [Model], withParentFilter: Bool = true) -> [Model] {
        var filtered = items
        if withParentFilter {
            if inspectorDisplayModel.listMode == .folder {
                filtered = items.filter { $0.parentId == nil }
            } else {
                filtered = items.filter { $0.category != .folder && $0.category != Model.collectionCategory }
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
    
    func expandedItems(items: [Model], level: Int = 0, withParentFilter: Bool = true, entryIds: [UUID: UUID] = [:]) -> [ItemListModel<Model>] {
        var total: [ItemListModel<Model>] = []
        guard level < 10 else { return total }
        let filtered = filteredItems(items: items, withParentFilter: withParentFilter)
        filtered.forEach { item in
            total.append(ItemListModel(id: entryIds[item.id, default: item.id], model: item, isOpen: listModel.isFolderOpen(itemId: item.id), level: level))
            if item.specialCategory && listModel.isFolderOpen(itemId: item.id) {
                let (newItems, newEntryIds) = item.subItems
                total.append(contentsOf: expandedItems(items: newItems, level: level + 1, withParentFilter: false, entryIds: newEntryIds))
            }
        }
        return total
    }
    
    @ViewBuilder
    var listView: some View {
        @Bindable var listModel = listModel
        List(selection: $listModel.listSelection) {
            itemRows()
        }
    }
    
    func itemRows() -> some View {
        ForEach(totalItems) { item in
            HStack {
                row(item.model.id)
                
                specialCategoryFolderIndicator(model: item.model)
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
    func specialCategoryFolderIndicator(model: Model) -> some View {
        if model.category == .folder || model.category == Model.collectionCategory {
            Image(systemName: listModel.isFolderOpen(itemId: model.id) ? "chevron.down" : "chevron.right")
                .imageScale(.small)
                .padding(.trailing)
                .foregroundStyle(listModel.isFolderOpen(itemId: model.id) ? Color.accentColor : Color.secondary)
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation { listModel.toggleFolder(itemId: model.id) }
                }
        }
    }
}

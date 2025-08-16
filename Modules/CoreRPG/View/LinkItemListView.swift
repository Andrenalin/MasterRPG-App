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
                }
        }
    }

    var contentView: some View {
        listView
            .frame(minWidth: 150, idealWidth: 250)
            .overlay {
                if filteredItems.isEmpty && !searchModel.searchText.isEmpty {
                    ContentUnavailableView.search
                }
            }
            //.listStyle(.plain)
            .environment(listModel)
            .animation(.smooth, value: filteredItems.count)
            .scrollIndicatorsFlash(onAppear: true)
            .scrollIndicatorsFlash(trigger: filteredItems.count)
            .scrollEdgeEffectStyle(.hard, for: .top)
#if !os(visionOS)
            .scrollDismissesKeyboard(.immediately)
#endif
    }
}

private extension LinkItemListView {
    
    var filteredItems: [Model] {
        var filtered: [Model]
        if inspectorDisplayModel.listMode == .folder {
            filtered = items
        } else {
            filtered = items.filter { $0.category != .folder && $0.category != Model.collectionCategory }
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
    var listView: some View {
        @Bindable var listModel = listModel
        List(selection: $listModel.listSelection) {
            itemRows()
        }
    }
    
    func itemRows() -> some View {
        ForEach(filteredItems) { item in
            row(item.id)
                .listRowInsets(EdgeInsets(top: 2, leading: leadingPadding, bottom: 2, trailing: 0))
        }
    }
    
    var leadingPadding: CGFloat {
        CGFloat(valueFor(iOS: 8, macOS: 4, tvOS: 8, visionOS: 8))
    }
}

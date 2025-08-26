// @copyright André Trettin

import CoreExternalRPG
import SwiftData
import SwiftUI

public struct OldLinkItemListView<ListController: OldListControllable, Row: View>: View where ListController.Model.ID == UUID {
    public init(listController: ListController, parentModel: ListController.Model?, isInspector: Bool, @ViewBuilder row: @escaping (UUID) -> Row) {
        self.listController = listController
        self.isInspector = isInspector
        self.row = row
        listController.listDisplayModel.listMode = parentModel?.category == .folder ? .folder : .list
    }

    let listController: ListController
    let isInspector: Bool
    let row: (UUID) -> Row

    @Environment(CacheItemListModel.self) private var cacheItemListModel
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
                    withAnimation {
                        listController.resetFilter()
                        cacheItemListModel.reset(search: searchModel.searchText)
                    }
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
        .environment(listModel)
        .environment(listController.searchModel)
    }

    var listModel: OldListModel {
        listController.listModel(for: nil)
    }

    var contentView: some View {
        listView
            .frame(minWidth: 150, idealWidth: 250)
            .overlay {
                if listModel.displayedItems.isEmpty && !listController.searchModel.searchText.isEmpty {
                    ContentUnavailableView.search
                }
            }
            .animation(.smooth, value: listModel.displayedItems.count)
        #if os(macOS)
            //.listStyle(.inset(alternatesRowBackgrounds: true))
            .listStyle(.sidebar)
        #endif
            .scrollIndicatorsFlash(onAppear: true)
            .scrollIndicatorsFlash(trigger: listModel.displayedItems.count)
#if !os(visionOS)
            .scrollEdgeEffectStyle(.hard, for: .top)
            .scrollDismissesKeyboard(.immediately)
#endif
    }
}

private extension OldLinkItemListView {
    @ViewBuilder
    var listView: some View {
        @Bindable var listModel = listModel
        List(selection: $listModel.listSelection) {
            itemRows()
        }
    }
    
    func itemRows() -> some View {
        ForEach(listModel.displayedItems) { item in
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
    func specialCategoryFolderIndicator(item: OldListItemModel) -> some View {
        if item.isSpecial {
            Image(systemName: item.isOpen ? "chevron.down" : "chevron.right")
                .imageScale(.small)
                .padding(.trailing)
                .foregroundStyle(item.isOpen ? Color.accentColor : Color.secondary)
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation { listController.toggleFolder(item: item) }
                }
        }
    }
}

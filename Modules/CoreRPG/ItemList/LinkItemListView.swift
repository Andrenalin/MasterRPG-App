// @copyright André Trettin

import CoreExternalRPG
import SwiftData
import SwiftUI

public struct LinkItemListView: View {
    init(root: any ItemRootControllable, parentModel: ItemDataModel?, isInspector: Bool) {
        self.root = root
        self.isInspector = isInspector
        //root.listLinkControllable.listDisplayModel.listMode = parentModel?.category == .folder ? .folder : .list
    }

    let root: any ItemRootControllable
    let isInspector: Bool

    @Environment(CacheItemListModel.self) private var cacheItemListModel
    @Environment(ListDisplayModel.self) private var listDisplayModel
    
    public var body: some View {
        NavigationStack {
            @Bindable var searchModel = root.listLinkControllable.searchModel
            @Bindable var inspectorDisplayModel = root.listLinkControllable.listDisplayModel
            
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
                    withAnimation { root.listLinkControllable.resetFilter() }
                }
                
                TextField("Filter", text: $searchModel.searchText)
                    .padding(.horizontal)
            }

            contentView
                .onChange(of: listDisplayModel.displayMode, initial: true) {
                    inspectorDisplayModel.displayMode = listDisplayModel.displayMode
                    withAnimation { root.listLinkControllable.resetFilter() }
                }
                .onChange(of: root.listLinkControllable.searchModel.searchText) {
                    withAnimation {
                        root.listLinkControllable.resetFilter()
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
                        .navigationTitle(root.module.title)
                }
        }
        .environment(root.listLinkControllable.listDisplayModel)
        .environment(root.listLinkControllable.searchModel)
    }

    var listModel: ListModel {
        root.listLinkControllable.listModel(for: nil)
    }

    var contentView: some View {
        listView
            .frame(minWidth: 150, idealWidth: 250)
            .overlay {
                if listModel.displayedItems.isEmpty && !root.listLinkControllable.searchModel.searchText.isEmpty {
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

private extension LinkItemListView {
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
                ItemRowView(root: root, model: item.model, cacheItemListModel: cacheItemListModel, isSelected: false) {
                    if root.viewControllable.thumbnailRowViewType == .custom {
                        root.viewControllable.thumbnailRowView(for: item.model.id)
                    } else if root.viewControllable.thumbnailRowViewType == .photo, let cacheController = root.cacheControllable {
                        ThumbnailRowPhotoView(cacheController: cacheController, model: item.model)
                    }
                }
                
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
        if item.model.specialCategory {
            Image(systemName: item.isOpen ? "chevron.down" : "chevron.right")
                .imageScale(.small)
                .padding(.trailing)
                .foregroundStyle(item.isOpen ? Color.accentColor : Color.secondary)
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation { root.listLinkControllable.toggleFolder(item: item) }
                }
        }
    }
}

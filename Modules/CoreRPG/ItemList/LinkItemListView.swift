// @copyright André Trettin

import CoreExternalRPG
import SwiftData
import SwiftUI

public struct LinkItemListView: View {
    init(root: any ItemRootControllable, type: LinkRootType, parentModel: ItemDataModel?) {
        self.root = root
        self.type = type
        root.listLinkControllable.listDisplayModel.listMode = parentModel?.category == .folder ? .folder : .list
    }

    let root: any ItemRootControllable
    let type: LinkRootType

    @Environment(CacheItemListModel.self) private var cacheItemListModel
    @Environment(ListDisplayModel.self) private var listDisplayModel
    
    public var body: some View {
        NavigationStack {
            if type == .inspector {
                pickerView
                
                filterFieldView
            }

            contentView
                .onChange(of: listDisplayModel.displayMode, initial: true) {
                    root.listLinkControllable.listDisplayModel.displayMode = listDisplayModel.displayMode
                    withAnimation { root.listLinkControllable.resetFilter() }
                }
                .onChange(of: root.listLinkControllable.listDisplayModel.listMode) {
                    withAnimation { root.listLinkControllable.resetFilter() }
                }
                .applyIf(type != .inspector) { content in
                    content
                        .toolbarItemListModifier(root: root, listControllable: root.listLinkControllable, parentModel: nil, modal: true)
                        .searchItemList(listControllable: root.listControllable)
                        .navigationTitle(root.module.title)
                }
        }
        .environment(root.listLinkControllable.listDisplayModel)
        .environment(root.listLinkControllable.searchModel)
    }
}

private extension LinkItemListView {
    var listModel: ListModel {
        root.listLinkControllable.listModel(for: nil)
    }

    @ViewBuilder
    var pickerView: some View {
        @Bindable var inspectorDisplayModel = root.listLinkControllable.listDisplayModel
        
        Picker(selection: $inspectorDisplayModel.listMode) {
            ForEach(ListDisplayModel.ListMode.allCases) { mode in
                Text(mode.title)
                    .tag(mode)
            }
        } label: {
            Text("List Mode", bundle: .module)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }
    
    @ViewBuilder
    var filterFieldView: some View {
        @Bindable var searchModel = root.listLinkControllable.searchModel
        
        TextField(text: $searchModel.searchText, prompt: textFieldText) {
            textFieldText
        }
        .labelsHidden()
        .textFieldStyle(.plain)
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.secondary, lineWidth: 1)
        }
        .padding(.horizontal)
        .onChange(of: searchModel.searchText) {
            withAnimation {
                root.listLinkControllable.resetFilter()
                cacheItemListModel.reset(search: searchModel.searchText)
            }
        }
    }
    
    var textFieldText: Text {
        Text("\(Image(systemName: "magnifyingglass")) Filter", bundle: .module)
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
#if !os(tvOS)
                .draggable(LinkData(itemId: item.model.id, module: root.module, name: item.model.name))
#endif

                specialCategoryFolderIndicator(item: item)
            }
            .selectListItem(isActive: type == .singleSelection || type == .mulitpleSelection) {
                root.singleSelectionModel.itemId = root.singleSelectionModel.itemId == item.model.id ? nil : item.model.id
            } isSelected: {
                root.singleSelectionModel.itemId == item.model.id
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

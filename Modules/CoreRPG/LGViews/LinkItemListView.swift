// @copyright André Trettin

import SwiftData
import SwiftUI

public struct LinkItemListView: View {
    init(root: any ItemRootControllable, type: LinkRootType, parentModel: (any ItemDataAccessable)?) {
        self.root = root
        self.type = type
        root.folderLinkControllable.listDisplayModel.listMode = parentModel?.category == .folder ? .folder : .list
    }

    let root: any ItemRootControllable
    let type: LinkRootType

    @Environment(CacheItemListModel.self) private var cacheItemListModel
    @Environment(ListDisplayModel.self) private var listDisplayModel
    @Environment(ItemSelectionModel.self) private var selectionModel
    
    public var body: some View {
        NavigationStack {
            if type == .inspector {
                pickerView
                
                filterFieldView
            }

            contentView
                .onChange(of: listDisplayModel.displayMode, initial: true) {
                    root.folderLinkControllable.listDisplayModel.displayMode = listDisplayModel.displayMode
                    withAnimation { root.folderLinkControllable.resetFilter() }
                }
                .onChange(of: root.folderLinkControllable.listDisplayModel.listMode) {
                    withAnimation { root.folderLinkControllable.resetFilter() }
                }
                .applyIf(type != .inspector) { content in
                    content
                        .toolbarItemListModifier(root: root, listControllable: root.folderLinkControllable, parentModel: nil, modal: true)
                        .searchItemList(listControllable: root.folderLinkControllable, parentModel: nil)
                        .navigationTitle(root.module.title)
                }
                .applyIf(type == .inspector) { content in
                    content
#if !os(macOS)
                        .toolbarVisibility(.hidden, for: .navigationBar)
#endif
                }
        }
        .environment(root.folderLinkControllable.listDisplayModel)
        .environment(root.folderLinkControllable.searchModel)
    }
}

private extension LinkItemListView {
    var listModel: FolderListModel {
        root.folderLinkControllable.listModel
    }

    @ViewBuilder
    var pickerView: some View {
        @Bindable var inspectorDisplayModel = root.folderLinkControllable.listDisplayModel
        
        Picker(selection: $inspectorDisplayModel.listMode) {
            ForEach(ListDisplayModel.ListMode.allCases) { mode in
                Text(mode.title)
                    .tag(mode)
            }
        } label: {
            Text("List Mode", bundle: .module)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }
    
    @ViewBuilder
    var filterFieldView: some View {
        @Bindable var searchModel = root.folderLinkControllable.searchModel
        
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
                root.folderLinkControllable.resetFilter()
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
                if listModel.displayedItems.isEmpty && !root.folderLinkControllable.searchModel.searchText.isEmpty {
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
            Group {
                if let entryId = item.entryId {
                    EntryRowView(root: root, item: item)
#if !os(tvOS)
            .draggable(for: root.module, itemId: item.model.id, entryId: entryId, name: item.model[entryId].name)
#endif
                } else {
                    itemRow(item: item)
                }
            }
            .selectListItem(isActive: type == .selection && selectionModel.canSelect(isCollection: item.model.specialCategory)) {
                withAnimation { selectionModel.toggleSelection(itemId: item.model.id, isCollection: item.model.specialCategory) }
            } isSelected: {
                selectionModel.itemId == item.model.id
            }
            .padding(.leading, CGFloat(item.level * 16))
            .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 0))
            .listRowSeparatorAll(item.isOpen ? .visible : .hidden, edges: .bottom)
        }
    }
    
    func itemRow(item: ListItemModel) -> some View {
        HStack {
            ItemRowView(root: root, model: item.model, cacheItemListModel: cacheItemListModel, isSelected: false) {
                if root.viewControllable.thumbnailRowViewType == .custom {
                    root.viewControllable.thumbnailRowView(for: item.model.id)
                } else if root.viewControllable.thumbnailRowViewType == .photo, let cacheController = root.cacheControllable {
                    ThumbnailRowPhotoView(cacheController: cacheController, model: item.model)
                }
            }
#if !os(tvOS)
            .draggable(for: root.module, itemId: item.model.id, entryId: nil, name: item.model.name)
#endif

            specialCategoryFolderIndicator(item: item)
        }
    }
    
    var leadingPadding: CGFloat {
        CGFloat(valueFor(iOS: 8, macOS: 4, tvOS: 8, visionOS: 8))
    }
    
    @ViewBuilder
    func specialCategoryFolderIndicator(item: ListItemModel) -> some View {
        if showFolderIndicator(item: item) {
            Image(systemName: item.isOpen ? "chevron.down" : "chevron.right")
                .imageScale(.small)
                .padding(.trailing)
                .foregroundStyle(item.isOpen ? Color.accentColor : Color.secondary)
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation { root.folderLinkControllable.toggleFolder(item: item) }
                }
        }
    }
    
    func showFolderIndicator(item: ListItemModel) -> Bool {
        item.model.specialCategory || (selectionModel.allowEntrySelection && !item.model.entries.isEmpty)
    }
}


struct EntryRowView: View {
    let root: any ItemRootControllable
    let item: ListItemModel
    
    
    var editController: (any EntryDataEditable)? {
        root.editControllable as? (any EntryDataEditable)
    }
    var body: some View {
        if let editController {
            EntryEditRow(editController: editController, entry: item.model[entryId], cacheItemListModel: root.editControllable.cacheItemListModel)
        } else {
            Text("\(item.model[entryId].name): \(item.model[entryId].content)")
        }
    }
    
    var entryId: UUID {
        item.entryId ?? UUID()
    }
}

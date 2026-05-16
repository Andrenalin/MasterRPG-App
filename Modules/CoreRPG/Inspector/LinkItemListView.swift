// @copyright André Trettin

import SwiftUI

public struct LinkItemListView: View {
    init(root: any ItemRootControllable, type: LinkRootType, selectionModel: ItemSelectionModel, parentModel: (any ItemDataAccessable)?) {
        self.root = root
        self.type = type
        self.selectionModel = selectionModel
        self.parentModel = parentModel
        if let parentModel {
            let mode: ListDisplayModel.ListMode = parentModel.category == .folder ? .folder : .list
            root.folderLinkControllable.listDisplayModel.listMode <=> mode
            root.folderLinkControllable.resetParentModel(model: parentModel)
        }
    }

    let root: any ItemRootControllable
    let type: LinkRootType
    let selectionModel: ItemSelectionModel
    let parentModel: (any ItemDataAccessable)?

#if os(macOS)
    @Environment(ScenesManager.self) private var scenesManager
#endif

    @State private var showDetails: Bool = false
    @State private var showDetailsView: (any NavigationDestination)? = nil

    // Plain text avoids NSTextAttachment re-resolution via UIKit TextField prompt path on every layout pass
    private static let filterPrompt = Text("Filter", bundle: .module)

    public var body: some View {
        let _ = Self._printChanges()
        ManagedNavigationStack(name: "LinkInspector") { navigator in
            VStack {
                if type == .inspector {
                    LinkItemPickerView(listDisplayModel: root.folderLinkControllable.listDisplayModel)

                    LinkItemFilterFieldView(
                        searchModel: root.folderLinkControllable.searchModel,
                        prompt: Self.filterPrompt
                    ) {
                        root.folderLinkControllable.resetFilter()
                        root.folderLinkControllable.cacheListItemModel.reset(search: root.folderLinkControllable.searchModel.searchText)
                    }
                }

                contentView
                    .tint(root.configurable.module.tint)
                    .onAppear {
                        root.folderLinkControllable.resetItemOnce()
                        withAnimation { root.folderLinkControllable.resetFilter() }
                    }
                    .onChange(of: root.folderLinkControllable.listDisplayModel.displayMode) {
                        withAnimation { root.folderLinkControllable.resetFilter() }
                    }
                    .onChange(of: root.folderLinkControllable.listDisplayModel.listMode) {
                        withAnimation { root.folderLinkControllable.resetFilter() }
                    }
                    .listModelUpdatesModifier(listControllable: root.folderLinkControllable, itemControllable: root.itemControllable)
                    .applyIf(type != .inspector && type != .selectionInline) { content in
                        content
                            .toolbarItemListModifier(root: root, listControllable: root.folderLinkControllable, parentModel: nil, modal: true)
                            .searchItemList(listControllable: root.folderLinkControllable)
                            .navigationTitle(root.configurable.module.title)
                    }
                    .applyIf(type == .inspector) { content in
                        content
#if !os(macOS)
                            .toolbarVisibility(.hidden, for: .navigationBar)
#endif
                    }
            }
            .onChange(of: showDetails) {
                guard let showDetailsView else { return }
                navigator.navigate(to: showDetailsView, method: .push)
            }
        }
    }
}

private extension LinkItemListView {
    var listModel: FolderListModel {
        root.folderLinkControllable.listModel
    }

    var displayItems: [ListItemModel] {
        parentModel == nil ? listModel.displayedItems : listModel.displayedParentItems
    }

    var contentView: some View {
        // Capture once — prevents multiple observation registrations per body update
        let items = displayItems
        let searchText = root.folderLinkControllable.searchModel.searchText
        return listView(items: items)
            .frame(minWidth: 150, idealWidth: 250)
            .overlay {
                if items.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView.search
                }
            }
            .animation(.smooth, value: items.count)
#if os(macOS)
            .listStyle(.sidebar)
#endif
            .scrollIndicatorsFlash(onAppear: true)
            .scrollIndicatorsFlash(trigger: items.count)
#if !os(visionOS)
            .scrollEdgeEffectStyle(.hard, for: .top)
            .scrollDismissesKeyboard(.immediately)
#endif
    }

    func listView(items: [ListItemModel]) -> some View {
        List {
            itemRows(items: items)
        }
    }

    func itemRows(items: [ListItemModel]) -> some View {
        ForEach(items) { item in
            Group {
                if let entryId = item.entryId {
                    HStack {
                        LinkEntryRowView(root: root, item: item, listDisplayModel: root.folderLinkControllable.listDisplayModel)

                        specialCategoryFolderIndicator(item: item)
                    }
                    .contentShape(.rect)
                    .contextMenu {
                        Button {
                            openDetail(for: item)
                        } label: {
                            Label("Open Details", systemImage: "arrow.up.right.square")
                        }
                        ControlGroup {
                            CompactDisplayModeToggle(listDisplayModel: root.folderLinkControllable.listDisplayModel)
                            MediumDisplayModeToggle(listDisplayModel: root.folderLinkControllable.listDisplayModel)
                            RegularDisplayModeToggle(listDisplayModel: root.folderLinkControllable.listDisplayModel)
                        }
                        ControlGroup {
                            ListModeToggle(listDisplayModel: root.folderLinkControllable.listDisplayModel)
                            FolderModeToggle(listDisplayModel: root.folderLinkControllable.listDisplayModel)
                        }
                        closeEntrySection(for: item)
                    }
#if !os(tvOS)
                    .draggable(for: root.configurable.module, itemId: item.model.id, entryId: entryId, name: item.model[entryId].name.withoutLink())
#endif
                } else {
                    itemRow(item: item)
                        .onTapGesture(count: 2) {
                            openDetail(for: item)
                        }
                        .accessibilityHint("Double-tap to open details")
                        .contextMenu {
                            Button {
                                openDetail(for: item)
                            } label: {
                                Label("Open Details", systemImage: "arrow.up.right.square")
                            }
                            ControlGroup {
                                CompactDisplayModeToggle(listDisplayModel: root.folderLinkControllable.listDisplayModel)
                                MediumDisplayModeToggle(listDisplayModel: root.folderLinkControllable.listDisplayModel)
                                RegularDisplayModeToggle(listDisplayModel: root.folderLinkControllable.listDisplayModel)
                            }
                            ControlGroup {
                                ListModeToggle(listDisplayModel: root.folderLinkControllable.listDisplayModel)
                                FolderModeToggle(listDisplayModel: root.folderLinkControllable.listDisplayModel)
                            }
                        }
                }
            }
            .selectListItem(isActive: isSelectionActive(item: item)) {
                withAnimation { selectionModel.toggleSelection(itemId: item.model.id, entryId: item.entryId, isCollection: item.model.specialCategory) }
            } isSelected: {
                selectionModel.selection.contains(where: { $0.itemId == item.model.id && $0.entryId == item.entryId })
            }
            .padding(.leading, CGFloat(item.level * 16))
            .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 0))
            .listRowSeparatorAll(item.isOpen || item.entryId != nil ? .visible : .hidden, edges: .bottom)
        }
    }

    func isSelectionActive(item: ListItemModel) -> Bool {
        (type == .selection || type == .selectionInline) && selectionModel.canSelect(isCollection: item.model.specialCategory, entryId: item.entryId)
    }

    func itemRow(item: ListItemModel) -> some View {
        HStack {
            ItemRowView(root: root, model: item.model, cacheItemListModel: root.folderLinkControllable.cacheListItemModel, listDisplayModel: root.folderLinkControllable.listDisplayModel, searchModel: root.folderLinkControllable.searchModel, isSelected: false) {
                if root.viewControllable.thumbnailRowViewType == .custom {
                    root.viewControllable.thumbnailRowView(for: item.model.id)
                } else if root.viewControllable.thumbnailRowViewType == .photo, let cacheController = root.cacheControllable {
                    ThumbnailRowPhotoView(cacheController: cacheController, model: item.model, cacheItemListModel: root.folderLinkControllable.cacheListItemModel, listDisplayModel: root.folderLinkControllable.listDisplayModel)
                }
            }
            .overlay(alignment: .trailing) {
                specialCategoryFolderIndicator(item: item)
            }
            .contentShape(.rect)
            .draggable(for: selectionModel.onlyEntrySelection ? .none : root.configurable.module, itemId: item.model.id, entryId: nil, name: item.model.name.withoutLink())
        }
    }

    func openDetail(for item: ListItemModel) {
#if os(macOS)
        guard !item.model.specialCategory else { return }
        scenesManager.openWindow(SceneId.viewerId(for: root.configurable.module), selection: WindowItemSelection(itemId: item.model.id))
#else
        if item.model.specialCategory {
            showDetailsView = root.folderLinkControllable.detailDestination(for: item.model.id)
        } else {
            showDetailsView = root.folderLinkControllable.viewerDestination(for: item.model.id)
        }
        withAnimation { showDetails.toggle() }
#endif
    }

    @ViewBuilder
    func specialCategoryFolderIndicator(item: ListItemModel) -> some View {
        if showFolderIndicator(item: item) {
            Button {
                withAnimation { root.folderLinkControllable.toggleFolder(item: item) }
            } label: {
                Image(systemName: item.isOpen ? "chevron.down" : "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(.red)
                    .contentShape(.circle)
                    .frame(width: 32, height: 32)
                #if !os(visionOS)
                    .glassEffect(.clear.interactive())
                #endif
            }
            .borderLessTVBottonStyle()
            .padding(.trailing, 4)
        }
    }

    func showFolderIndicator(item: ListItemModel) -> Bool {
        item.model.specialCategory || (selectionModel.allowEntrySelection && !item.model.entries.isEmpty && item.entryId == nil) || !root.itemControllable.subChildren(itemId: item.model.id, entryId: item.entryId).isEmpty
    }

    func closeEntrySection(for item: ListItemModel) -> some View {
        Button {
            withAnimation { root.folderLinkControllable.toggleParentFolder(item: item) }
        } label: {
            Label {
                Text("Close parent folder", bundle: .module)
            } icon: {
                Image(systemName: "folder.circle")
            }
        }
    }
}

// @copyright André Trettin

import SwiftUI

public struct LinkItemListView: View {
    init(root: any ItemRootControllable, type: LinkRootType, selectionModel: ItemSelectionModel, parentModel: (any ItemDataAccessable)?) {
        self.root = root
        self.type = type
        self.selectionModel = selectionModel
        self.parentModel = parentModel
        self._parentModelId = State(initialValue: parentModel?.id)
        self._scrollPosition = State(initialValue: root.folderLinkControllable.listModel.scrollId)
    }

    let root: any ItemRootControllable
    let type: LinkRootType
    let selectionModel: ItemSelectionModel
    let parentModel: (any ItemDataAccessable)?

    @State private var parentModelId: UUID?
    @State private var scrollPosition: UUID?

#if os(macOS)
    @Environment(ScenesManager.self) private var scenesManager
#endif

    @State private var showDetails: Bool = false
    @State private var showDetailsView: (any NavigationDestination)? = nil

    private static let filterPrompt = Text("Filter", bundle: .module)

    public var body: some View {
        ManagedNavigationStack(name: "LinkInspector") { navigator in
            VStack {
                if type == .inspector {
                    LinkItemPickerView(
                        listDisplayModel: root.folderLinkControllable.listDisplayModel,
                        isParentFiltering: parentModel != nil
                    )

                    LinkItemFilterFieldView(
                        searchModel: root.folderLinkControllable.searchModel,
                        prompt: Self.filterPrompt
                    ) {
                        root.folderLinkControllable.cacheListItemModel.reset(search: root.folderLinkControllable.searchModel.searchText)
                        Task { await root.folderLinkControllable.performSearch() }
                    }
                }

                contentView
                    .tint(root.configurable.module.tint)
                    .task(id: parentModelId) {
                        await configureParentFiltering()
                    }
                    .onAppear {
                        let savedScroll = root.folderLinkControllable.listModel.scrollId
                        Task {
                            await root.folderLinkControllable.resetItemOnce()
                            root.folderLinkControllable.resetFilter()
                            root.folderLinkControllable.listModel.scrollId = savedScroll
                            if let savedPosition = root.folderLinkControllable.listModel.scrollId {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    scrollPosition = savedPosition
                                }
                            }
                        }
                    }
                    .onChange(of: root.folderLinkControllable.listDisplayModel.displayMode) {
                        root.folderLinkControllable.resetFilter()
                    }
                    .onChange(of: root.folderLinkControllable.listDisplayModel.listMode) {
                        root.folderLinkControllable.resetFilter()
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

    var displayItems: [FolderListItemModel] {
        listModel.list
    }

    func configureParentFiltering() async {
        if let parentModel {
            root.folderLinkControllable.searchModel.filterId = parentModel.id
            let mode: ListDisplayModel.ListMode = parentModel.category == .folder ? .folder : .list
            if root.folderLinkControllable.listDisplayModel.listMode != mode {
                root.folderLinkControllable.listDisplayModel.listMode = mode
            }
            root.folderLinkControllable.resetParentModel(model: parentModel)
        } else {
            root.folderLinkControllable.searchModel.filterId = nil
            if root.folderLinkControllable.listModel.parentModel != nil {
                root.folderLinkControllable.listModel.parentModel = nil
                root.folderLinkControllable.resetFilter()
            }
        }
    }

    @ViewBuilder
    var contentView: some View {
        let items = displayItems
        let searchText = root.folderLinkControllable.searchModel.searchText
        let isEmpty = items.isEmpty && !searchText.isEmpty

        listView(items: items)
            .frame(minWidth: 150, idealWidth: 250)
            .overlay {
                if isEmpty {
                    ContentUnavailableView.search
                }
            }
            .animation(.smooth, value: items.map(\.id))
            .scrollIndicatorsFlash(onAppear: true)
#if !os(visionOS)
            .scrollDismissesKeyboard(.immediately)
#endif
    }

    func listView(items: [FolderListItemModel]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: []) {
                ForEach(items) { item in
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            itemRowContent(item: item)
                                .selectListItem(isActive: isSelectionActive(item: item)) {
                                    selectionModel.toggleSelection(
                                        itemId: item.source.itemId,
                                        entryId: item.source.entryId,
                                        isCollection: itemModel(item)?.specialCategory ?? false
                                    )
                                } isSelected: {
                                    selectionModel.selection.contains(where: {
                                        $0.itemId == item.source.itemId && $0.entryId == item.source.entryId
                                    })
                                }
                        }
                        .padding(.leading, CGFloat(item.level * 4 + 8))
                        .padding(.trailing, 8)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(backgroundForLevel(item.level))
                        .contentShape(.rect)

                        if item.isOpen || item.source.entryId != nil {
                            Divider()
                                .padding(.leading, 8)
                        }
                    }
                    .id(item.id)
                }
            }
            .frame(maxWidth: .infinity)
            .scrollTargetLayout()
        }
        .scrollPosition(id: $scrollPosition, anchor: .top)
        .onChange(of: scrollPosition) { _, newValue in
            root.folderLinkControllable.listModel.scrollId = newValue
        }
    }

    func itemModel(_ item: FolderListItemModel) -> (any ItemDataAccessable)? {
        root.itemControllable.itemSync(for: item.source.itemId)
    }

    @ViewBuilder
    private func itemRowContent(item: FolderListItemModel) -> some View {
        if let entryId = item.source.entryId {
            entryRow(item: item, entryId: entryId)
        } else {
            standardItemRow(item: item)
        }
    }

    private func entryRow(item: FolderListItemModel, entryId: UUID) -> some View {
        HStack {
            LinkEntryRowView(root: root, item: item, listDisplayModel: root.folderLinkControllable.listDisplayModel)
            specialCategoryFolderIndicator(item: item)
        }
        .contextMenu {
            contextMenu(for: item)
        }
        .draggableWithOverlay(for: root.configurable.module, itemId: item.source.itemId, entryId: entryId, name: itemModel(item)?[entryId].name.withoutLink() ?? "")
    }

    private func standardItemRow(item: FolderListItemModel) -> some View {
        itemRow(item: item)
            .onTapGesture(count: 2) {
                openDetail(for: item)
            }
            .accessibilityHint(Text("Double-tap to open details", bundle: .module))
            .contextMenu {
                contextMenu(for: item)
            }
    }

    @ViewBuilder
    private func contextMenu(for item: FolderListItemModel) -> some View {
        Button {
            openDetail(for: item)
        } label: {
            Label { Text("Open Details", bundle: .module) } icon: { Image(systemName: "arrow.up.right.square") }
        }

        displayModeControls
        listModeControls

        if item.source.entryId != nil {
            closeEntrySection(for: item)
        }
    }

    @ViewBuilder
    private var displayModeControls: some View {
        ControlGroup {
            CompactDisplayModeToggle(listDisplayModel: root.folderLinkControllable.listDisplayModel)
            MediumDisplayModeToggle(listDisplayModel: root.folderLinkControllable.listDisplayModel)
            RegularDisplayModeToggle(listDisplayModel: root.folderLinkControllable.listDisplayModel)
        }
    }

    @ViewBuilder
    private var listModeControls: some View {
        if parentModel == nil {
            ControlGroup {
                ListModeToggle(listDisplayModel: root.folderLinkControllable.listDisplayModel)
                FolderModeToggle(listDisplayModel: root.folderLinkControllable.listDisplayModel)
            }
        }
    }

    func isSelectionActive(item: FolderListItemModel) -> Bool {
        (type == .selection || type == .selectionInline) &&
        selectionModel.canSelect(isCollection: itemModel(item)?.specialCategory ?? false, entryId: item.source.entryId)
    }

    func itemRow(item: FolderListItemModel) -> some View {
        ItemRowView(
            root: root,
            model: itemModel(item) ?? root.itemControllable.itemOrEmpty(for: item.source.itemId),
            cacheItemListModel: root.folderLinkControllable.cacheListItemModel,
            listDisplayModel: root.folderLinkControllable.listDisplayModel,
            searchModel: root.folderLinkControllable.searchModel,
            isSelected: false
        ) {
            if root.viewControllable.thumbnailRowViewType == .custom {
                root.viewControllable.thumbnailRowView(for: item.source.itemId)
            } else if root.viewControllable.thumbnailRowViewType == .photo, let cacheController = root.cacheControllable {
                ThumbnailRowPhotoView(cacheController: cacheController, model: itemModel(item) ?? root.itemControllable.itemOrEmpty(for: item.source.itemId), listDisplayModel: root.folderLinkControllable.listDisplayModel)
            }
        }
        .draggableWithOverlay(for: selectionModel.onlyEntrySelection ? .none : root.configurable.module, itemId: item.source.itemId, entryId: nil, name: itemModel(item)?.name.withoutLink() ?? "")
        .overlay(alignment: .trailing) {
            specialCategoryFolderIndicator(item: item)
        }
    }

    func openDetail(for item: FolderListItemModel) {
#if os(macOS)
        guard itemModel(item)?.specialCategory != true else { return }
        scenesManager.openWindow(SceneId.viewerId(for: root.configurable.module), selection: WindowItemSelection(itemId: item.source.itemId))
#else
        if itemModel(item)?.specialCategory == true {
            showDetailsView = root.folderLinkControllable.detailDestination(for: item.source.itemId)
        } else {
            showDetailsView = root.folderLinkControllable.viewerDestination(for: item.source.itemId)
        }
        showDetails.toggle()
#endif
    }

    @ViewBuilder
    func specialCategoryFolderIndicator(item: FolderListItemModel) -> some View {
        if showFolderIndicator(item: item) {
            Button {
                Task { await root.folderLinkControllable.toggleFolder(item: item) }
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

    func showFolderIndicator(item: FolderListItemModel) -> Bool {
        let model = itemModel(item)
        return model?.specialCategory == true ||
        (selectionModel.allowEntrySelection && !(model?.entries.isEmpty ?? true) && item.source.entryId == nil) ||
        (item.source.entryId != nil && item.isOpen)
    }

    func closeEntrySection(for item: FolderListItemModel) -> some View {
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

    @ViewBuilder
    func backgroundForLevel(_ level: Int) -> some View {
        if level > 0 {
            if level % 2 == 1 {
                Color.secondary.opacity(0.2)
            } else {
                Color.primary.opacity(0.2)
            }
        }
    }
}

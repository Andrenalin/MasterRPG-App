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
                        // Fix 2: use scheduleSearch() — cancels any in-flight search via didSet
                        root.folderLinkControllable.scheduleSearch()
                    }
                }

                contentView
                    .tint(root.configurable.module.tint)
                    // Fix 1: inline configureParentFiltering — it had no await, async was misleading
                    .task(id: parentModelId) {
                        root.folderLinkControllable.resetParent(model: parentModel)
                    }
                    .onAppear {
                        let savedScroll = root.folderLinkControllable.listModel.scrollId
                        Task {
                            // Fix 3: resetItemOnce() already calls performSearch() → resetFilter()
                            // internally; remove the redundant explicit resetFilter() call.
                            await root.folderLinkControllable.resetItemOnce()
                            root.folderLinkControllable.listModel.scrollId = savedScroll
                            if let savedPosition = root.folderLinkControllable.listModel.scrollId {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    scrollPosition = savedPosition
                                }
                            }
                        }
                    }
                    // Fix 4: displayMode affects which fields are searched — must re-search,
                    // not just rebuild the list from stale results.
                    .onChange(of: root.folderLinkControllable.listDisplayModel.displayMode) {
                        root.folderLinkControllable.scheduleSearch()
                    }
                    // listMode switches between flat (list) and hierarchical (folder) — the search
                    // pipeline produces completely different structures, so a full re-search is needed.
                    .onChange(of: root.folderLinkControllable.listDisplayModel.listMode) {
                        root.folderLinkControllable.scheduleSearch()
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

// MARK: - Private helpers

private extension LinkItemListView {
    var listModel: FolderListModel {
        root.folderLinkControllable.listModel
    }

    @ViewBuilder
    var contentView: some View {
        let items = listModel.list
        let isEmpty = items.isEmpty && !root.folderLinkControllable.searchModel.searchText.isEmpty

        listView(items: items)
            .frame(minWidth: 150, idealWidth: 250)
            .overlay {
                if isEmpty { ContentUnavailableView.search }
            }
            // Fix 8: items.map(\.id) allocates O(n) on every render; .count is O(1)
            // and sufficient for add/remove animations.
            .animation(.smooth, value: items.count)
            .scrollIndicatorsFlash(onAppear: true)
#if !os(visionOS)
            .scrollDismissesKeyboard(.immediately)
#endif
    }

    func listView(items: [FolderListItemModel]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: []) {
                // Fix 7: each row is its own struct so SwiftUI can skip unchanged rows.
                ForEach(items) { item in
                    VStack(spacing: 0) {
                        InspectorRowView(
                            root: root,
                            item: item,
                            selectionModel: selectionModel,
                            type: type,
                            showListModeControls: parentModel == nil,
                            showDetails: $showDetails,
                            showDetailsView: $showDetailsView
                        )

                        if item.isOpen || item.source.entryId != nil {
                            Divider().padding(.leading, 8)
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
}

// MARK: - InspectorRowView
// Extracted from LinkItemListView so SwiftUI can skip body evaluation for rows
// whose inputs (item, selection state) have not changed.

private struct InspectorRowView: View {
    let root: any ItemRootControllable
    let item: FolderListItemModel
    let selectionModel: ItemSelectionModel
    let type: LinkRootType
    let showListModeControls: Bool

    @Binding var showDetails: Bool
    @Binding var showDetailsView: (any NavigationDestination)?

#if os(macOS)
    @Environment(ScenesManager.self) private var scenesManager
#endif

    var body: some View {
        // Fix 5: resolve model once per row — no more 3× itemSync calls.
        let model = root.itemControllable.itemSync(for: item.source.itemId)

        HStack(spacing: 0) {
            rowContent(model: model)
                .selectListItem(isActive: isSelectionActive(model: model)) {
                    selectionModel.toggleSelection(
                        itemId: item.source.itemId,
                        entryId: item.source.entryId,
                        isCollection: model?.specialCategory ?? false
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
    }

    // MARK: Row content

    @ViewBuilder
    private func rowContent(model: (any ItemDataAccessable)?) -> some View {
        if let entryId = item.source.entryId {
            entryRow(model: model, entryId: entryId)
        } else {
            standardItemRow(model: model)
        }
    }

    private func entryRow(model: (any ItemDataAccessable)?, entryId: UUID) -> some View {
        HStack {
            LinkEntryRowView(root: root, item: item, listDisplayModel: root.folderLinkControllable.listDisplayModel)
            folderChevron
        }
        .contextMenu { rowContextMenu(model: model) }
        .draggableWithOverlay(
            for: root.configurable.module,
            itemId: item.source.itemId,
            entryId: entryId,
            name: model?[entryId].name.withoutLink() ?? ""
        )
    }

    private func standardItemRow(model: (any ItemDataAccessable)?) -> some View {
        itemRowView(model: model)
            .onTapGesture(count: 2) { openDetail(model: model) }
            .accessibilityHint(Text("Double-tap to open details", bundle: .module))
            .contextMenu { rowContextMenu(model: model) }
    }

    private func itemRowView(model: (any ItemDataAccessable)?) -> some View {
        let resolved = model ?? root.itemControllable.itemOrEmpty(for: item.source.itemId)
        return ItemRowView(
            root: root,
            model: resolved,
            cacheItemListModel: root.folderLinkControllable.cacheListItemModel,
            listDisplayModel: root.folderLinkControllable.listDisplayModel,
            searchModel: root.folderLinkControllable.searchModel,
            isSelected: false
        ) {
            if root.viewControllable.thumbnailRowViewType == .custom {
                root.viewControllable.thumbnailRowView(for: item.source.itemId)
            } else if root.viewControllable.thumbnailRowViewType == .photo,
                      let cacheController = root.cacheControllable {
                ThumbnailRowPhotoView(
                    cacheController: cacheController,
                    model: resolved,
                    listDisplayModel: root.folderLinkControllable.listDisplayModel
                )
            }
        }
        .draggableWithOverlay(
            for: selectionModel.onlyEntrySelection ? .none : root.configurable.module,
            itemId: item.source.itemId,
            entryId: nil,
            name: resolved.name.withoutLink()
        )
        .overlay(alignment: .trailing) { folderChevron }
    }

    // MARK: Folder chevron

    /// Fix 6: uses `item.canOpen` (set by search pipeline) instead of calling itemSync.
    @ViewBuilder
    private var folderChevron: some View {
        if item.canOpen || item.isOpen {
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
        } else if shouldShowEntryChevron {
            // Entry-level chevron (allowEntrySelection): still needs model to check entries
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

    private var shouldShowEntryChevron: Bool {
        guard selectionModel.allowEntrySelection, item.source.entryId == nil else { return false }
        return !(root.itemControllable.itemSync(for: item.source.itemId)?.entries.isEmpty ?? true)
    }

    // MARK: Helpers

    private func isSelectionActive(model: (any ItemDataAccessable)?) -> Bool {
        (type == .selection || type == .selectionInline) &&
        selectionModel.canSelect(
            isCollection: model?.specialCategory ?? false,
            entryId: item.source.entryId
        )
    }

    private func openDetail(model: (any ItemDataAccessable)?) {
#if os(macOS)
        guard model?.specialCategory != true else { return }
        scenesManager.openWindow(
            SceneId.viewerId(for: root.configurable.module),
            selection: WindowItemSelection(itemId: item.source.itemId)
        )
#else
        if model?.specialCategory == true {
            showDetailsView = root.folderLinkControllable.detailDestination(for: item.source.itemId)
        } else {
            showDetailsView = root.folderLinkControllable.viewerDestination(for: item.source.itemId)
        }
        showDetails.toggle()
#endif
    }

    @ViewBuilder
    private func rowContextMenu(model: (any ItemDataAccessable)?) -> some View {
        Button {
            openDetail(model: model)
        } label: {
            Label { Text("Open Details", bundle: .module) } icon: { Image(systemName: "arrow.up.right.square") }
        }

        ControlGroup {
            CompactDisplayModeToggle(listDisplayModel: root.folderLinkControllable.listDisplayModel)
            MediumDisplayModeToggle(listDisplayModel: root.folderLinkControllable.listDisplayModel)
            RegularDisplayModeToggle(listDisplayModel: root.folderLinkControllable.listDisplayModel)
        }

        if showListModeControls {
            ControlGroup {
                ListModeToggle(listDisplayModel: root.folderLinkControllable.listDisplayModel)
                FolderModeToggle(listDisplayModel: root.folderLinkControllable.listDisplayModel)
            }
        }

        if item.source.entryId != nil {
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

    @ViewBuilder
    private func backgroundForLevel(_ level: Int) -> some View {
        if level > 0 {
            if level % 2 == 1 {
                Color.secondary.opacity(0.2)
            } else {
                Color.primary.opacity(0.2)
            }
        }
    }
}

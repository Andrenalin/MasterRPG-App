// @copyright André Trettin

import SwiftUI

public struct LinkItemListView: View {
    init(root: any ItemRootControllable, type: LinkRootType, selectionModel: ItemSelectionModel, parentModel: (any ItemDataAccessable)?) {
        self.root = root
        self.type = type
        self.selectionModel = selectionModel
        self.parentModel = parentModel
        self._parentModelId = State(initialValue: parentModel?.id)
        // Scroll position comes from whichever model is active.
        // detailListModel may not exist yet at init time, so fall back to main.
        let initScrollId = parentModel != nil
            ? (root.folderLinkControllable.listModel.detailListModel?.scrollId
               ?? root.folderLinkControllable.listModel.scrollId)
            : root.folderLinkControllable.listModel.scrollId
        self._scrollPosition = State(initialValue: initScrollId)
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
                        // When scoped to a parent, re-run the detail search; otherwise main search.
                        if parentModel != nil {
                            root.folderLinkControllable.scheduleDetailSearch()
                        } else {
                            root.folderLinkControllable.scheduleSearch()
                        }
                    }
                }

                UnavailableGlassOverlay(isUnavialable: root.folderLinkControllable.searchModel.searchReturnedNoResults) {
                    contentView
                }
                .tint(root.configurable.module.tint)
                    // When parentModel changes: create/reset detailListModel (with deep-copied cache
                    // for warm start) then run a scoped detail search via inspectorSearchResults.
                    // When parentModel clears: tear down detailListModel and resume main search.
                    .task(id: parentModelId) {
                        if let parent = parentModel {
                            root.folderLinkControllable.resetDetail(model: parent)
                        } else {
                            root.folderLinkControllable.listModel.detailListModel = nil
                            root.folderLinkControllable.searchModel.filterId = nil
                            root.folderLinkControllable.scheduleSearch()
                        }
                    }
                    .onAppear {
                        let savedScroll = listModel.scrollId
                        Task {
                            // Only prime the main list once; detailListModel is handled by .task above.
                            if parentModel == nil {
                                await root.folderLinkControllable.resetItemOnce()
                            }
                            listModel.scrollId = savedScroll
                            if let savedPosition = listModel.scrollId {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    scrollPosition = savedPosition
                                }
                            }
                        }
                    }
                    // displayMode / listMode changes: scoped → detail search; unscoped → main search.
                    .onChange(of: root.folderLinkControllable.listDisplayModel.displayMode) {
                        if parentModel != nil {
                            root.folderLinkControllable.scheduleDetailSearch()
                        } else {
                            root.folderLinkControllable.scheduleSearch()
                        }
                    }
                    .onChange(of: root.folderLinkControllable.listDisplayModel.listMode) {
                        if parentModel != nil {
                            root.folderLinkControllable.scheduleDetailSearch()
                        } else {
                            root.folderLinkControllable.scheduleSearch()
                        }
                    }
                    // When parentModel != nil, pass it to the modifier so it observes entry
                    // changes and calls performDetailSearch() automatically.
                    .listModelUpdatesModifier(
                        listControllable: root.folderLinkControllable,
                        itemControllable: root.itemControllable,
                        parentModel: parentModel
                    )
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
    /// Routes to `detailListModel` when a parent scope is active, exactly as `ListRootView` does.
    /// This keeps the scoped inspector state (entries, open/close, scroll) independent from
    /// the unscoped inspector so switching back doesn't reset the main list.
    var listModel: FolderListModel {
        if parentModel != nil, let detail = root.folderLinkControllable.listModel.detailListModel {
            return detail
        }
        return root.folderLinkControllable.listModel
    }

    @ViewBuilder
    var contentView: some View {
        let items = listModel.list
        // searchReturnedNoResults rather than items.isEmpty for the same reason as ListRootView:
        // buildList preserves the old list when search returns nothing, so items.isEmpty is always false.
        let isEmpty = root.folderLinkControllable.searchModel.searchReturnedNoResults

        listView(items: items)
            .frame(minWidth: 150, idealWidth: 250)
            .overlay {
                if isEmpty { ContentUnavailableView.search }
            }
            .animation(.smooth, value: items.count)
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
            listModel.scrollId = newValue
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
        // Use the pre-resolved model from FolderListItemModel (set by mapResult via itemSync).
        // This is always correct for entry rows: model points to the item whose entry is displayed,
        // e.g. the sub-value model for group entries — no extra itemSync needed in the view.
        let model = item.model

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
        // Only render as an entry row when the entry genuinely belongs to this item's model.
        // Folder children also carry a non-nil `source.entryId` — it's the parent folder's
        // membership entry UUID used for SwiftUI identity (`FolderListItemModel.id`).
        // That entry lives in the parent's model, not the child's, so `model[membershipId]`
        // returns nil/empty → blank row. Checking model.entries avoids this.
        if let entryId = item.source.entryId,
           model?.entries.contains(where: { $0.id == entryId }) == true {
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

    @ViewBuilder
    private var folderChevron: some View {
        // Same three-way condition as SpecialCategoryFolderIndicator — see that struct for rationale.
        if item.canOpen || item.isOpen || item.wasExplicitlyClosed {
            Button {
                root.folderLinkControllable.toggleFolder(item: item)
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

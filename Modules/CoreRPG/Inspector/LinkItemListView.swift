// @copyright André Trettin

import SwiftUI

public struct LinkItemListView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    init(root: any ItemRootControllable, type: LinkRootType, selectionModel: ItemSelectionModel, parentModel: (any ItemDataAccessable)?) {
        self.root = root
        self.type = type
        self.selectionModel = selectionModel
        self.parentModel = parentModel
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

    @State private var scrollPosition: UUID?
    @State private var showDetails: Bool = false
    @State private var showDetailsView: (any NavigationDestination)? = nil
    @State private var generationSelection: WindowItemSelection?
    
    private static let filterPrompt = Text("Filter", bundle: .module)

    public var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        
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

                UnavailableGlassOverlay(isUnavailable: shouldShowNoResults) {
                    contentView
                }
                .moduleTint(root.configurable.module)
                    // When parentModel changes: create/reset detailListModel (with deep-copied cache
                    // for warm start) then run a scoped detail search via inspectorSearchResults.
                    // When parentModel clears: tear down detailListModel and resume main search.
                    .task(id: parentModel?.id) {
                        if let parent = parentModel {
                            root.folderLinkControllable.resetDetail(model: parent)
                        } else {
                            root.folderLinkControllable.listModel.detailListModel = nil
                            root.folderLinkControllable.searchModel.filterId = nil
                            root.folderLinkControllable.scheduleSearch()
                        }
                    }
                    .task {
                        let savedScroll = listModel.scrollId
                        // Only prime the main list once; detailListModel is handled by .task above.
                        if parentModel == nil {
                            await root.folderLinkControllable.resetItemOnce()
                        }
                        guard !Task.isCancelled else { return }
                        listModel.scrollId = savedScroll
                        if let savedPosition = listModel.scrollId {
                            withAnimation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                scrollPosition = savedPosition
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
                            .navigationTitle(Text(verbatim: root.configurable.module.title))
                    }
                    .applyIf(type == .inspector) { content in
                        content
                            .navigationVisibility(false)
                    }
            }
            .onChange(of: showDetails) {
                guard let showDetailsView else { return }
                navigator.navigate(to: showDetailsView, method: .push)
            }
            .itemGenerationPresentation(
                root: root,
                selection: $generationSelection
            )
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
    
    /// Determines if the "no results" overlay should be shown.
    ///
    /// Uses `searchModel.searchReturnedNoResults` rather than `listModel.list.isEmpty`: `buildList`
    /// preserves the previous list when a search returns nothing (anti-flicker), so `list.isEmpty`
    /// is never true even when the search matched zero items.
    var shouldShowNoResults: Bool {
        root.folderLinkControllable.searchModel.searchReturnedNoResults
    }

    @ViewBuilder
    var contentView: some View {
        let items = listModel.list

        listView(items: items)
            .frame(minWidth: 150, idealWidth: 250)
            .animation(accessibilityReduceMotion ? nil : .smooth, value: items.count)
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

#Preview {
    LinkItemListView(
        root: ItemRootController.fake,
        type: .inspector,
        selectionModel: ItemSelectionModel(),
        parentModel: nil
    )
}

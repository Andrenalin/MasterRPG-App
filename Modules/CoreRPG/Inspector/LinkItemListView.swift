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

    // Plain text avoids NSTextAttachment re-resolution via UIKit TextField prompt path on every layout pass
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
                        // This task runs whenever parentModelId changes (including initial load)
                        // It ensures parent filtering is properly configured for this specific view
                        await configureParentFiltering()
                    }
                    .onAppear {
                        let savedScroll = root.folderLinkControllable.listModel.scrollId
                        root.folderLinkControllable.listModel.searchExpandsEntries = true
                        root.folderLinkControllable.resetItemOnce()
                        root.folderLinkControllable.resetFilter()
                        root.folderLinkControllable.listModel.scrollId = savedScroll
                        
                        if let savedPosition = root.folderLinkControllable.listModel.scrollId {
                            // Use withAnimation instead of Task.sleep for more reliable timing
                            // SwiftUI will coordinate this with the view's appearance
                            withAnimation(.easeInOut(duration: 0.2)) {
                                scrollPosition = savedPosition
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

    var displayItems: [ListItemModel] {
        parentModel == nil ? listModel.displayedItems : listModel.displayedParentItems
    }
    
    /// Configures parent filtering for this view
    /// This ensures the correct items are displayed based on whether we're showing
    /// a parent-filtered view or the full list
    func configureParentFiltering() async {
        if let parentModel {
            // Scope inspector search to this item
            root.folderLinkControllable.searchModel.filterId = parentModel.id
            let mode: ListDisplayModel.ListMode = parentModel.category == .folder ? .folder : .list
            if root.folderLinkControllable.listDisplayModel.listMode != mode {
                print("!!!! Here !! \(mode)")
                root.folderLinkControllable.listDisplayModel.listMode = mode
            }
            root.folderLinkControllable.resetParentModel(model: parentModel)
        } else {
            root.folderLinkControllable.searchModel.filterId = nil
            if root.folderLinkControllable.listModel.parentModel != nil {
                root.folderLinkControllable.listModel.parentModel = nil
                root.folderLinkControllable.listModel.parentOriginalItems = []
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

    func listView(items: [ListItemModel]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: []) {
                ForEach(items) { item in
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            itemRowContent(item: item)
                                .selectListItem(isActive: isSelectionActive(item: item)) {
                                    selectionModel.toggleSelection(itemId: item.model.id, entryId: item.entryId, isCollection: item.model.specialCategory)
                                } isSelected: {
                                    selectionModel.selection.contains(where: { $0.itemId == item.model.id && $0.entryId == item.entryId })
                                }
                        }
                        .padding(.leading, CGFloat(item.level * 4 + 8))
                        .padding(.trailing, 8)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(backgroundForLevel(item.level))
                        .contentShape(.rect)
                        
                        if item.isOpen || item.entryId != nil {
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

    @ViewBuilder
    private func itemRowContent(item: ListItemModel) -> some View {
        if let entryId = item.entryId {
            entryRow(item: item, entryId: entryId)
        } else {
            standardItemRow(item: item)
        }
    }
    
    private func entryRow(item: ListItemModel, entryId: UUID) -> some View {
        HStack {
            LinkEntryRowView(root: root, item: item, listDisplayModel: root.folderLinkControllable.listDisplayModel)
            specialCategoryFolderIndicator(item: item)
        }
        .contextMenu {
            contextMenu(for: item)
        }
        .draggableWithOverlay(for: root.configurable.module, itemId: item.model.id, entryId: entryId, name: item.model[entryId].name.withoutLink())
    }
    
    private func standardItemRow(item: ListItemModel) -> some View {
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
    private func contextMenu(for item: ListItemModel) -> some View {
        Button {
            openDetail(for: item)
        } label: {
            Label { Text("Open Details", bundle: .module) } icon: { Image(systemName: "arrow.up.right.square") }
        }
        
        displayModeControls
        listModeControls
        
        // Only show close entry section for entries
        if item.entryId != nil {
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
        // Only show list mode controls if parent filtering is not active
        if parentModel == nil {
            ControlGroup {
                ListModeToggle(listDisplayModel: root.folderLinkControllable.listDisplayModel)
                FolderModeToggle(listDisplayModel: root.folderLinkControllable.listDisplayModel)
            }
        }
    }

    func isSelectionActive(item: ListItemModel) -> Bool {
        (type == .selection || type == .selectionInline) && selectionModel.canSelect(isCollection: item.model.specialCategory, entryId: item.entryId)
    }

    func itemRow(item: ListItemModel) -> some View {
        ItemRowView(root: root, model: item.model, cacheItemListModel: root.folderLinkControllable.cacheListItemModel, listDisplayModel: root.folderLinkControllable.listDisplayModel, searchModel: root.folderLinkControllable.searchModel, isSelected: false) {
            if root.viewControllable.thumbnailRowViewType == .custom {
                root.viewControllable.thumbnailRowView(for: item.model.id)
            } else if root.viewControllable.thumbnailRowViewType == .photo, let cacheController = root.cacheControllable {
                ThumbnailRowPhotoView(cacheController: cacheController, model: item.model, listDisplayModel: root.folderLinkControllable.listDisplayModel)
            }
        }
        .draggableWithOverlay(for: selectionModel.onlyEntrySelection ? .none : root.configurable.module, itemId: item.model.id, entryId: nil, name: item.model.name.withoutLink())
        .overlay(alignment: .trailing) {
            specialCategoryFolderIndicator(item: item)
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
        showDetails.toggle()
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
        // specialCategory items are folders that can always be toggled.
        // Non-special items show an indicator when entry selection is allowed and they have entries.
        // Entry rows (entryId != nil) only show a toggle when they are already open (sub-children loaded).
        item.model.specialCategory ||
        (selectionModel.allowEntrySelection && !item.model.entries.isEmpty && item.entryId == nil) ||
        (item.entryId != nil && item.isOpen)
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
    
    /// Returns a subtle background color that alternates based on hierarchy level
    /// to help users visually distinguish between different nesting levels
    @ViewBuilder
    func backgroundForLevel(_ level: Int) -> some View {
        if level > 0 {
            // Alternate between slightly darker shades for each level
            if level % 2 == 1 {
                Color.secondary.opacity(0.2)
            } else {
                Color.primary.opacity(0.2)
            }
        }
    }
}

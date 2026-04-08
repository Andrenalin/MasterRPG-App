// @copyright André Trettin

import SwiftData
import SwiftUI

public struct LinkItemListView: View {
    init(root: any ItemRootControllable, type: LinkRootType, parentModel: (any ItemDataAccessable)?) {
        self.root = root
        self.type = type
        self.parentModel = parentModel
        if let parentModel {
            let mode: ListDisplayModel.ListMode = parentModel.category == .folder ? .folder : .list
            root.folderLinkControllable.listDisplayModel.listMode <=> mode
            root.folderLinkControllable.resetParentModel(model: parentModel)
        }
    }

    let root: any ItemRootControllable
    let type: LinkRootType
    let parentModel: (any ItemDataAccessable)?

    @Environment(CacheItemListModel.self) private var cacheItemListModel
    @Environment(ItemSelectionModel.self) private var selectionModel
#if os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif

    @State private var showDetails: Bool = false
    @State private var showDetailsView: (any NavigationDestination)? = nil

    // Plain text avoids NSTextAttachment re-resolution via UIKit TextField prompt path on every layout pass
    private static let filterPrompt = Text("Filter", bundle: .module)

    public var body: some View {
        ManagedNavigationStack(name: "LinkInspector") { navigator in
            VStack {
                if type == .inspector {
                    LinkItemPickerView(listDisplayModel: root.folderLinkControllable.listDisplayModel)

                    LinkItemFilterFieldView(
                        searchModel: root.folderLinkControllable.searchModel,
                        prompt: Self.filterPrompt
                    ) {
                        root.folderLinkControllable.resetFilter()
                        cacheItemListModel.reset(search: root.folderLinkControllable.searchModel.searchText)
                    }
                }

                contentView
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
                        EntryRowView(root: root, item: item)

                        specialCategoryFolderIndicator(item: item)
                    }
                    .contentShape(.rect)
                    .contextMenu {
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
            ItemRowView(root: root, model: item.model, cacheItemListModel: cacheItemListModel, isSelected: false) {
                if root.viewControllable.thumbnailRowViewType == .custom {
                    root.viewControllable.thumbnailRowView(for: item.model.id)
                } else if root.viewControllable.thumbnailRowViewType == .photo, let cacheController = root.cacheControllable {
                    ThumbnailRowPhotoView(cacheController: cacheController, model: item.model)
                }
            }
            .overlay(alignment: .trailing) {
                specialCategoryFolderIndicator(item: item)
            }
            .contentShape(.rect)
#if !os(tvOS)
            .draggable(for: selectionModel.onlyEntrySelection ? .none : root.configurable.module, itemId: item.model.id, entryId: nil, name: item.model.name.withoutLink())
#endif
        }
    }

    func openDetail(for item: ListItemModel) {
#if os(macOS)
        guard !item.model.specialCategory else { return }
        openWindow(id: root.configurable.module.viewerWindowId, value: WindowItemSelection(itemId: item.model.id))
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

// MARK: - Extracted subviews to scope @Bindable allocations

/// Picker subview — @Bindable is allocated only when this subview's dependencies change,
/// not on every LinkItemListView body update.
private struct LinkItemPickerView: View {
    @Bindable var listDisplayModel: ListDisplayModel

    var body: some View {
        Picker(selection: $listDisplayModel.listMode) {
            ForEach(ListDisplayModel.ListMode.allCases) { mode in
                Text(mode.title, bundle: .module)
                    .tag(mode)
            }
        } label: {
            Text("List Mode", bundle: .module)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }
}

/// Filter field subview — @Bindable allocation and Text prompt construction are scoped here,
/// not recomputed on every parent body update.
private struct LinkItemFilterFieldView: View {
    @Bindable var searchModel: SearchModel
    let prompt: Text
    let onSearchChange: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .imageScale(.small)
            TextField(text: $searchModel.searchText, prompt: prompt) {
                prompt
            }
#if os(iOS)
            .autocapitalization(.none)
            .textContentType(.name)
#endif
            .disableAutocorrection(true)
            .labelsHidden()
            .submitLabel(.return)
            .textFieldStyle(.plain)
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.secondary, lineWidth: 1)
        }
        .padding(.horizontal)
        .onChange(of: searchModel.searchText) {
            withAnimation {
                onSearchChange()
            }
        }
    }
}

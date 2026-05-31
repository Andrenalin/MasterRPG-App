// @copyright André Trettin

import SwiftUI

@Observable
public final class FolderListModel {
    public init(isSelectionMode: Bool = false, selection: [String] = [], navigationModel: ModuleNavigationModel) {
        self.isSelectionMode = isSelectionMode
        self.selection = selection
        self.listSelection = Set(selection)
        self.navigationModel = navigationModel
        update(selection: Set(selection))
    }

    public init(parentModel: (any ItemDataAccessable)?, navigationModel: ModuleNavigationModel) {
        self.parentModel = parentModel
        self.selectedParentId = parentModel?.id
        self.isSelectionMode = false
        self.selection = []
        self.listSelection = []
        self.navigationModel = navigationModel
    }
    
    // MARK: - Navigation
    @ObservationIgnored public let navigationModel: ModuleNavigationModel

    // MARK: - Items
    @ObservationIgnored var parentModel: (any ItemDataAccessable)?
    public var parentItemId: UUID? { parentModel?.id }

    @ObservationIgnored var updatedOnce: Bool = false
    @ObservationIgnored var originalItems: [ListItemModel] = []
    @ObservationIgnored var parentOriginalItems: [ListItemModel] = []

    // Search
    @ObservationIgnored var searchTask: Task<Void, Never>? = nil
    public var searchExpandsEntries: Bool = false

    public var displayedItems: [ListItemModel] = []
    public var displayedParentItems: [ListItemModel] = []

    // MARK: - List item cache
    // Maps a stable semantic key (from ItemRowModel.stableListId or a context-qualified variant)
    // to the ListItemModel that was first created for that position.
    // Returning the same instance across rebuilds keeps ListItemModel.listId stable, which in
    // turn keeps SwiftUI identity stable — no unnecessary destroy/recreate animations.
    // The Character/groups edge case (same item appears multiple times) uses a context-qualified
    // key (e.g. "folder-<parentId>-<itemId>") so each appearance gets its own entry.
    @ObservationIgnored private var listItemCache: [String: ListItemModel] = [:]

    // Pre-built display arrays for each structural mode.
    // Switching between list and folder view is then O(1) — just swap displayedItems.
    // Search sets isHidden on the existing ListItemModel objects instead of rebuilding arrays.
    @ObservationIgnored var cachedListModeItems: [ListItemModel] = []
    @ObservationIgnored var cachedFolderModeItems: [ListItemModel] = []

    // Returns the cached instance for `key`, or calls `create` once and caches the result.
    func cachedItem(key: String, create: () -> ListItemModel) -> ListItemModel {
        if let existing = listItemCache[key] { return existing }
        let item = create()
        listItemCache[key] = item
        return item
    }

    // Clears the cache. Call when the item data model is fully replaced (e.g. account switch).
    func clearListItemCache() {
        listItemCache.removeAll()
        cachedListModeItems.removeAll()
        cachedFolderModeItems.removeAll()
    }

    var addedModelId: UUID?
    
    // MARK: - List navigation
    public var selectedParentId: UUID?
    public var lastFolderId: UUID?
    @ObservationIgnored private var folderOpenStates: [String: Bool] = [:]
    var level: Int = 0

    public func isFolderOpen(itemId: UUID, entryId: UUID?) -> Bool {
        folderOpenStates[folderKey(itemId: itemId, entryId: entryId)] ?? false
    }

    // Returns the persisted open state if the user has ever toggled this item, otherwise
    // records `defaultOpen` and returns it. Search result builders call this so that
    // auto-opened folders can be toggled closed (and stay closed across resetFilter calls).
    func openState(itemId: UUID, entryId: UUID?, defaultOpen: Bool) -> Bool {
        let key = folderKey(itemId: itemId, entryId: entryId)
        if let existing = folderOpenStates[key] { return existing }
        folderOpenStates[key] = defaultOpen
        return defaultOpen
    }

    func toggleFolder(itemId: UUID, entryId: UUID?) {
        let key = folderKey(itemId: itemId, entryId: entryId)
        folderOpenStates[key] = !(folderOpenStates[key] ?? false)
    }

    private func folderKey(itemId: UUID, entryId: UUID?) -> String {
        "\(itemId.uuidString)-\(entryId?.uuidString ?? "self")"
    }
        
    // MARK: - Selection
    private var isSelectionMode: Bool
    public var selection: [String]
    public var selected: String?
    public var listSelection: Set<String>

    // MARK: - Scroll
    
    var scrollId: String?
    
    // MARK: - ListModels
    @ObservationIgnored var subListModel: FolderListModel?
    
    // MARK: - Routing
    public var itemRoute: UUID?
    public var subFolderRoute: UUID?
}

// MARK: - Items
extension FolderListModel {
    func deleteItems(ids: [String]) -> [ItemRowModel] {
        let removed = ids.compactMap { id -> ItemRowModel? in
            guard let index = displayedItems.firstIndex(where: { $0.id == id }) else { return nil }
            let model = displayedItems[index].model
            deleteItems(offsets: IndexSet(integer: index))
            return ItemRowModel(itemId: model.id, typeId: .none)
        }
        return removed
    }
    
    func deleteItems(offsets: IndexSet) {
        for index in offsets {
            if displayedItems[index].id == selected {
                resetListSelection()
                update(selection: Set())
            }
        }
        displayedItems.remove(atOffsets: offsets)
    }

    func restoreItems(models: [ItemRowModel]) {
        let itemsToRestore = models.compactMap { model in
            originalItems.first(where: { $0.model.id == model.itemId })
        }

        for itemToRestore in itemsToRestore {
            if !displayedItems.contains(where: { $0.model.id == itemToRestore.model.id }) {
                // Find the correct position based on originalItems order
                if let originalIndex = originalItems.firstIndex(where: { $0.model.id == itemToRestore.model.id }) {
                    // Find where to insert in displayedItems to maintain order
                    var insertIndex = 0
                    for displayedItem in displayedItems {
                        if let displayedOriginalIndex = originalItems.firstIndex(where: { $0.model.id == displayedItem.model.id }),
                           displayedOriginalIndex < originalIndex {
                            insertIndex += 1
                        } else {
                            break
                        }
                    }
                    displayedItems.insert(itemToRestore, at: insertIndex)
                }
            }
        }
    }
    
    func item(itemId: UUID?) -> ListItemModel? {
        guard let itemId else { return nil }
        return displayedItems.first(where: { $0.model.id == itemId })
    }
}

// MARK: - Selection

public extension FolderListModel {
    func resetListSelection() {
        listSelection <=> []
    }

    func update(selectionMode: Bool) {
        isSelectionMode <=> selectionMode
        if isSelectionMode {
            selection <=> []
        } else if let selected {
            selection <=> [selected]
        }
    }

    func update(selection: Set<String>) {
        if isSelectionMode {
            self.selection <=> Array(selection)
        } else {
            if selected != selection.first {
                selected = selection.first
            }
        }
    }

    func set(selectedItemId: UUID) {
        selected = displayedParentItems.first(where: { $0.model.id == selectedItemId })?.id ?? displayedItems.first(where: { $0.model.id == selectedItemId })?.id
    }

    var selectedItemId: UUID? {
        displayedParentItems.first(where: { $0.id == selected })?.model.id ??
        displayedItems.first(where: { $0.id == selected })?.model.id
    }

    var selectedModel: (any ItemDataAccessable)? {
        displayedParentItems.first(where: { $0.id == selected })?.model ??
        displayedItems.first(where: { $0.id == selected })?.model
    }

    var selectionItemIds: [UUID] {
        selection.compactMap { selected in
            displayedParentItems.first(where: { $0.id == selected })?.model.id ??
            displayedItems.first(where: { $0.id == selected })?.model.id
        }
    }
        
    func ids(selectedItemIds: [UUID]) -> [String] {
        selectedItemIds.compactMap { itemId -> String? in
            displayedParentItems.first(where: { $0.model.id == itemId })?.id ??
            displayedItems.first(where: { $0.model.id == itemId })?.id
        }
    }
}

// MARK: - Navigation

public extension FolderListModel {
    func resetListModel() {
        subFolderRoute = nil
        resetListSelection()
        update(selection: Set())
        subListModel = nil
    }
}

@Observable
public final class ListItemModel: Identifiable {
    // Preferred init: `key` is the cache key, which also becomes the stable SwiftUI id.
    // Key format: ItemRowModel.stableListId for root items, or "<parentId>-<stableListId>"
    // for items nested under a folder/collection. This ensures items that appear under multiple
    // parents (collection mode, Character groups) each get a distinct, stable identity.
    public init(key: String, source: ItemRowModel, model: any ItemDataAccessable, isOpen: Bool = false, level: Int = 0) {
        self.listId = UUID()
        self.source = source
        self.id = key
        self.model = model
        self.isOpen = isOpen
        self.lastIsOpen = isOpen
        self.entryId = source.entryId
        self.level = level
    }

    // Legacy init: keeps existing call sites compiling during the cache wiring migration.
    // Once all map() / mapSub() / search-builder call sites use cachedItem(), this can be removed.
    public init(id: String, model: any ItemDataAccessable, isOpen: Bool = false, entryId: UUID? = nil, level: Int = 0) {
        self.listId = UUID()
        self.source = ItemRowModel(itemId: model.id, entryId: entryId, typeId: .none)
        self.id = id
        self.model = model
        self.isOpen = isOpen
        self.lastIsOpen = isOpen
        self.entryId = entryId
        self.level = level
    }

    // Stable UUID — assigned once at init. The cache ensures the same instance (and UUID)
    // is returned across rebuilds. Used for reverse-lookup if needed.
    public let listId: UUID

    // Semantic identity: itemId + entryId + typeId.
    // The cache in FolderListModel keys on a context-qualified variant of this.
    public let source: ItemRowModel

    // SwiftUI Identifiable id. Equals the cache key, so it is stable across rebuilds
    // as long as the cached instance is returned by FolderListModel.cachedItem(key:create:).
    public let id: String

    let model: any ItemDataAccessable
    var isOpen: Bool
    var lastIsOpen: Bool
    var isHidden: Bool = false
    let entryId: UUID?
    public let level: Int
}

extension ListItemModel: Equatable {
    public static func == (lhs: ListItemModel, rhs: ListItemModel) -> Bool {
        lhs.id == rhs.id
        && lhs.listId == rhs.listId
        && lhs.model.id == rhs.model.id
        && lhs.isOpen == rhs.isOpen
        && lhs.entryId == rhs.entryId
        && lhs.level == rhs.level
        && lhs.isHidden == rhs.isHidden
    }
}

// @copyright André Trettin

import SwiftUI

@MainActor @Observable
public final class FolderListModel {
    public init(isSelectionMode: Bool = false, selection: [UUID] = [], navigationModel: ModuleNavigationModel) {
        self.isSelectionMode = isSelectionMode
        self.selection = selection
        self.listSelection = Set(selection)
        self.navigationModel = navigationModel
        update(selection: Set(selection))
    }

    public init(parentModel: (any ItemDataAccessible)?, navigationModel: ModuleNavigationModel) {
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
    @ObservationIgnored var parentModel: (any ItemDataAccessible)?
    public var parentItemId: UUID? { parentModel?.id }

    @ObservationIgnored var updatedOnce: Bool = false

    // MARK: - Display list
    public var list: [FolderListItemModel] = [] {
        didSet { rowIndex = nil }
    }
    /// Rows by row id and by item id, built on the first lookup after `list` changes: selection,
    /// menu commands and folder actions looked rows up with a linear scan on every body
    /// evaluation. See CODE_AUDIT_Folder §7.4.
    @ObservationIgnored private var rowIndex: (byId: [UUID: FolderListItemModel], byItemId: [UUID: FolderListItemModel])?
    public var cacheListModels: [UUID: FolderListItemModel] = [:]
    // MARK: - List navigation
    public var selectedParentId: UUID?
    var level: Int = 0
    var addedModelId: UUID?
    var selectionGeneration: Int = 0

    /// The last queued `FolderListControllable.add(type:url:root:)` call, `nil` once every queued
    /// add finished. A plain Add is ignored while it is set (double-tap protection); adds that
    /// carry a dropped file queue behind it. See CODE_AUDIT_Folder §3.2.
    @ObservationIgnored var addItemTask: Task<Void, Never>?
    @ObservationIgnored var addItemToken: UUID?

    // MARK: - Selection
    private var isSelectionMode: Bool
    public var selection: [UUID]
    public var selected: UUID?
    public var listSelection: Set<UUID>

    // MARK: - Scroll
    
    var scrollId: UUID?
    var lastNonNilScrollId: UUID?
    
    // MARK: - ListModels
    public var detailListModel: FolderListModel?
    
    // MARK: - Routing
    public var itemRoute: UUID?
    public var subFolderRoute: UUID?
}

// MARK: - Scroll Restoration

extension FolderListModel {
    func recordVisibleScrollPosition(_ id: UUID?) {
        guard let id, row(id: id) != nil else { return }
        lastNonNilScrollId = id
    }

    func restoredScrollTarget(
        selection: UUID?,
        prioritizesSelection: Bool = false
    ) -> UUID? {
        if prioritizesSelection,
           let selection,
           row(id: selection) != nil {
            return selection
        }
        if let lastNonNilScrollId,
           row(id: lastNonNilScrollId) != nil {
            return lastNonNilScrollId
        }
        if let selection,
           row(id: selection) != nil {
            return selection
        }
        return nil
    }
}

// MARK: - Items

extension FolderListModel {
    func deleteItems(ids: [UUID]) -> [ItemRowModel] {
        let removed = ids.compactMap { id -> ItemRowModel? in
            guard let index = list.firstIndex(where: { $0.source.itemId == id }) else { return nil }
            let itemId = list[index].source.itemId
            deleteItems(offsets: IndexSet(integer: index))
            return ItemRowModel(itemId: itemId, typeId: .none)
        }
        return removed
    }

    func deleteItems(offsets: IndexSet) {
        for index in offsets {
            if list[index].id == selected {
                resetListSelection()
                update(selection: Set())
            }
            if list[index].id == scrollId {
                scrollId = nil
            }
            if list[index].id == lastNonNilScrollId {
                lastNonNilScrollId = nil
            }
            // Regular-width (iPad) layouts drive the NavigationSplitView detail column from
            // navigationModel.selectedItemId directly, independently of `selected` above — clear
            // it too, or the detail column keeps showing the just-deleted item.
            if list[index].source.itemId == navigationModel.selectedItemId {
                navigationModel.selectedItemId = nil
                navigationModel.selectedEntryId = nil
            }
        }
        for index in offsets.reversed() {
            cacheListModels.removeValue(forKey: list[index].id)
        }
        list.remove(atOffsets: offsets)
    }

    func item(itemId: UUID?) -> FolderListItemModel? {
        guard let itemId else { return nil }
        return row(itemId: itemId)
    }

    /// The row with this row id.
    func row(id: UUID) -> FolderListItemModel? {
        indexedRows().byId[id]
    }

    /// The first row showing this item, as `list.first { $0.source.itemId == itemId }`.
    func row(itemId: UUID) -> FolderListItemModel? {
        indexedRows().byItemId[itemId]
    }

    private func indexedRows() -> (byId: [UUID: FolderListItemModel], byItemId: [UUID: FolderListItemModel]) {
        // Read through the getter, so a view using a lookup still observes `list`.
        let rows = list
        if let rowIndex { return rowIndex }
        var byId: [UUID: FolderListItemModel] = [:]
        var byItemId: [UUID: FolderListItemModel] = [:]
        for row in rows {
            if byId[row.id] == nil { byId[row.id] = row }
            if byItemId[row.source.itemId] == nil { byItemId[row.source.itemId] = row }
        }
        let index = (byId, byItemId)
        rowIndex = index
        return index
    }
}

// MARK: - Detail List

public extension FolderListModel {
    func resetParent(model: (any ItemDataAccessible)?) {
        resetListModel(parentModel: model)
    }
    
    @MainActor func resetDetailList(parentModel: any ItemDataAccessible) {
        if detailListModel == nil {
            detailListModel = FolderListModel(parentModel: parentModel, navigationModel: navigationModel)
        } else {
            detailListModel?.resetListModel(parentModel: parentModel)
        }
        // Deep-copy relevant cached items so the detail model is independent from the main list.
        // Copies the parent item itself (CharacterRPG: character is the focal parent) and any
        // direct children (folder/collection case). Deep copies mean open/close state in the
        // detail view does not bleed into the main list's cache.
        let childItemIds = Set(parentModel.entries.map(\.childId))
        for (key, cached) in cacheListModels {
            let isParent = cached.source.itemId == parentModel.id
            let isChild  = childItemIds.contains(cached.source.itemId)
            // Warm-start from the main list only for items the detail cache hasn't seen yet.
            // Rows left from a previously-focused parent are kept as-is, so switching back to that
            // character (or folder) redisplays instantly instead of rebuilding from scratch.
            guard isParent || isChild, detailListModel?.cacheListModels[key] == nil else { continue }
            detailListModel?.cacheListModels[key] = cached.deepCopy()
        }
    }
}

// MARK: - Selection

public extension FolderListModel {
    func resetNavigationSelection() {
        selectionGeneration &+= 1
        addedModelId = nil
        itemRoute = nil
        resetListSelection()
        update(selection: Set())
    }

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

    func update(selection: Set<UUID>) {
        if isSelectionMode {
            self.selection <=> Array(selection)
        } else {
            if selected != selection.first {
                selected = selection.first
            }
        }
    }

    func set(selectedItemId: UUID) {
        // Resolve to FolderListItemModel.id (may be entryId for folder children)
        selected = row(itemId: selectedItemId)?.id ?? selectedItemId
    }

    var selectedItemId: UUID? {
        guard let selected else { return nil }
        // For folder children id == entryId; return the actual item UUID for navigation
        return row(id: selected)?.source.itemId ?? selected
    }

    /// The item ids of the selected rows. `selection` holds row ids, which for a row inside an
    /// expanded folder or collection are entry or path ids, not item ids; passing them on
    /// unchanged made every multi-select action skip those rows. See CODE_AUDIT_Folder §5.7.
    var selectionItemIds: [UUID] {
        selection.map { rowId in
            row(id: rowId)?.source.itemId ?? rowId
        }
    }
}

// MARK: - Navigation

public extension FolderListModel {
    func resetListModel(parentModel: (any ItemDataAccessible)?) {
        self.parentModel = parentModel
        selectedParentId = parentModel?.id
        subFolderRoute = nil
        resetListSelection()
        update(selection: Set())
        detailListModel = nil
    }
}

@MainActor @Observable
public final class FolderListItemModel: Identifiable, Sendable, Equatable, Hashable {
    public init(id: UUID, source: ItemRowModel, destination: ItemRowModel?, level: Int, isShown: Bool, lastIsShown: Bool = false, isHidden: Bool = false, isFolded: Bool = false) {
        self.id = id
        self.source = source
        self.destination = destination ?? source
        self.level = level
        self.isOpen = isShown
        self.lastIsOpen = lastIsShown
        self.isHidden = isHidden
        self.isFolded = isFolded
    }
    
    // identifier
    public let id: UUID
    public let source: ItemRowModel // for reference it could be link to another module
    public let destination: ItemRowModel // is the same as source if not link
    public var level: Int

    // display state
    public var isOpen: Bool
    public var lastIsOpen: Bool = false
    public var isHidden: Bool = false
    public var isFolded: Bool = false
    
    // children
    public var parentId: UUID?
    public var children: [FolderListItemModel] = []
    /// True when the item has expandable children that weren't returned in the last search result
    /// (lazy folder/collection or inspector entry-group). Drives chevron display and fold actions
    /// without requiring an extra itemSync lookup.
    public var canOpen: Bool = false

    /// When set, `loadChildrenViaSearch` uses this UUID as the focusId instead of `source.itemId`.
    /// Used for character inspector group entries: `source.itemId` = characterId (navigation),
    /// `childFocusId` = entry.valueId (the sub-value item whose entries load on expand).
    public var childFocusId: UUID? = nil

    /// Set by `toggleFolder` (close branch) so `appendToFlat` skips auto-opening this item even
    /// when search results include matching children. Cleared when the user explicitly opens it.
    /// Distinguishes "user closed" (wasExplicitlyClosed=true) from "never interacted" (false).
    public var wasExplicitlyClosed: Bool = false

    /// Direct reference to the domain model for this row.
    /// Set by `mapResult` via `itemSync` so views never need a separate `itemSync` call.
    /// Not included in equality/hash — identity is defined by `id`/`source`, not model content.
    public var model: (any ItemDataAccessible)? = nil

    /// Creates an independent copy of this item and its entire children tree.
    /// Used by `resetDetailLink` to seed a `detailListModel` with pre-loaded items from the
    /// main list without sharing references — each model can evolve independently.
    public func deepCopy() -> FolderListItemModel {
        let copy = FolderListItemModel(
            id: id,
            source: source,
            destination: destination,
            level: level,
            isShown: isOpen,
            lastIsShown: lastIsOpen,
            isHidden: isHidden,
            isFolded: isFolded
        )
        copy.parentId          = parentId
        copy.canOpen           = canOpen
        copy.childFocusId      = childFocusId
        copy.wasExplicitlyClosed = wasExplicitlyClosed
        copy.model             = model        // same reference — model is shared, not deep-copied
        copy.children          = children.map { $0.deepCopy() }
        return copy
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(source)
        hasher.combine(destination)
        hasher.combine(level)
    }

    public static func == (lhs: FolderListItemModel, rhs: FolderListItemModel) -> Bool {
        // Rebuilt lists reuse the cached row instances, and `@Observable` compares the old and
        // new `list` on every assignment: without this, each comparison walked every row's
        // whole children tree. See CODE_AUDIT_Folder §7.4.
        if lhs === rhs { return true }
        return lhs.id == rhs.id &&
        lhs.source == rhs.source &&
        lhs.destination == rhs.destination &&
        lhs.level == rhs.level &&
        lhs.isOpen == rhs.isOpen &&
        lhs.lastIsOpen == rhs.lastIsOpen &&
        lhs.isHidden == rhs.isHidden &&
        lhs.isFolded == rhs.isFolded &&
        lhs.children == rhs.children
    }
    
    func model(root: RootManager) -> (any ItemDataAccessible)? {
        root.itemRootController(for: source.typeId)?.itemControllable.itemSync(for: source.itemId)
    }
}

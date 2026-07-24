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

    // MARK: - Display list
    public var list: [FolderListItemModel] = []
    public var cacheListModels: [UUID: FolderListItemModel] = [:]
    var isFirstSearch = true
    var wasSearching = false
    
    // MARK: - List navigation
    public var selectedParentId: UUID?
    public var lastFolderId: UUID?
    var level: Int = 0
    var addedModelId: UUID?
    var selectionGeneration: Int = 0

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
        }
        for index in offsets.reversed() {
            cacheListModels.removeValue(forKey: list[index].id)
        }
        list.remove(atOffsets: offsets)
    }

    func item(itemId: UUID?) -> FolderListItemModel? {
        guard let itemId else { return nil }
        return list.first(where: { $0.source.itemId == itemId })
    }
}

// MARK: - Detail List

public extension FolderListModel {
    func resetParent(model: (any ItemDataAccessable)?) {
        resetListModel(parentModel: model)
    }
    
    @MainActor func resetDetailList(parentModel: any ItemDataAccessable) {
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
        selected = list.first(where: { $0.source.itemId == selectedItemId })?.id ?? selectedItemId
    }

    var selectedItemId: UUID? {
        guard let selected else { return nil }
        // For folder children id == entryId; return the actual item UUID for navigation
        return list.first(where: { $0.id == selected })?.source.itemId ?? selected
    }

    var selectionItemIds: [UUID] {
        selection
    }

    func ids(selectedItemIds: [UUID]) -> [UUID] {
        selectedItemIds
    }
}

// MARK: - Navigation

public extension FolderListModel {
    func resetListModel(parentModel: (any ItemDataAccessable)?) {
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
    public var model: (any ItemDataAccessable)? = nil

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
    
    func model(root: RootManager) -> (any ItemDataAccessable)? {
        root.itemRootController(for: source.typeId)?.itemControllable.itemSync(for: source.itemId)
    }
}

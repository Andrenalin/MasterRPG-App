// @copyright André Trettin

import SwiftUI

enum RangeSelectionMode: Equatable {
    case select
    case deselect
}

struct RangeSelection {
    let anchorId: UUID
    let mode: RangeSelectionMode
    /// The selection from before the range started.
    let base: Set<UUID>
}

extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
    /// The content of the list's `LazyVStack`: its rows' frames and a drag's location share it.
    static var listRows: NamedCoordinateSpace { .named("listRows") }
}

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
    /// The row the keyboard acts on in selection mode: the last row clicked or moved to with the
    /// arrow keys. `@FocusState` alone lost it, because the focus can sit on the row's checkmark
    /// button instead of the row button, and then up / down restarted at the first row and Space
    /// had no row to toggle.
    @ObservationIgnored public var keyboardRowId: UUID?
    /// The range being selected or deselected by a drag over the rows or by Shift + arrow.
    @ObservationIgnored var rangeSelection: RangeSelection?
    /// The rows' frames in the `.listRows` coordinate space, reported by the rows in selection
    /// mode. Maps the pointer position of a drag to a row.
    @ObservationIgnored var rowFrames: [UUID: CGRect] = [:]

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

    /// Drops the cached rows `isGone` names, except those in the list. The cache gained a row
    /// for every id ever shown and lost one only on a local delete, so the rows of items that
    /// sync, an import rollback or a game end removed stayed for the life of the list model,
    /// each holding its item model. See CODE_AUDIT_21 §7.6.
    func pruneCache(isGone: (FolderListItemModel) -> Bool) {
        guard !cacheListModels.isEmpty else { return }
        let listed = Set(list.map(\.id))
        let stale = cacheListModels.values.filter { !listed.contains($0.id) && isGone($0) }.map(\.id)
        guard !stale.isEmpty else { return }
        for id in stale {
            cacheListModels.removeValue(forKey: id)
        }
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

    /// Adds the row to the multi-selection, or removes it when it is already selected.
    func toggleListSelection(of rowId: UUID) {
        if listSelection.contains(rowId) {
            listSelection.remove(rowId)
        } else {
            listSelection.insert(rowId)
        }
    }

    /// The row `offset` rows after (positive) or before (negative) `currentId`, stopping at the
    /// first and last row. Without a current row, or when it is not in the list (filtered
    /// away), the first row for a step down and the last row for a step up.
    func rowId(offsetBy offset: Int, from currentId: UUID?) -> UUID? {
        guard !list.isEmpty else { return nil }
        guard let currentId, let currentIndex = list.firstIndex(where: { $0.id == currentId }) else {
            return offset > 0 ? list.first?.id : list.last?.id
        }
        return list[min(max(currentIndex + offset, 0), list.count - 1)].id
    }

    var isRangeSelecting: Bool { rangeSelection != nil }

    /// Starts a range at `rowId`. The row's own state decides what the range does: a selected row
    /// starts a deselecting range, an unselected row a selecting one. The rows the range covers
    /// follow `extendRangeSelection(to:)`.
    func beginRangeSelection(at rowId: UUID) {
        guard list.contains(where: { $0.id == rowId }) else { return }
        rangeSelection = RangeSelection(
            anchorId: rowId,
            mode: listSelection.contains(rowId) ? .deselect : .select,
            base: listSelection
        )
        extendRangeSelection(to: rowId)
    }

    /// Selects or deselects every row from the range's first row to `rowId`, on top of the
    /// selection from before the range. Moving back shrinks the range again.
    func extendRangeSelection(to rowId: UUID) {
        guard let range = rangeSelection,
              let anchorIndex = list.firstIndex(where: { $0.id == range.anchorId }),
              let targetIndex = list.firstIndex(where: { $0.id == rowId }) else { return }
        let covered = list[min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)].map(\.id)
        let updated = range.mode == .select ? range.base.union(covered) : range.base.subtracting(covered)
        if updated != listSelection {
            listSelection = updated
        }
    }

    func endRangeSelection() {
        rangeSelection = nil
    }

    /// The row at `y` in the `.listRows` space, or the nearest one when `y` is in a gap or beyond
    /// the first or last row reported.
    func rowId(atY y: CGFloat) -> UUID? {
        var best: (id: UUID, distance: CGFloat)?
        for row in list {
            guard let frame = rowFrames[row.id] else { continue }
            let distance = y < frame.minY ? frame.minY - y : max(0, y - frame.maxY)
            if best == nil || distance < best?.distance ?? .infinity {
                best = (row.id, distance)
            }
        }
        return best?.id
    }

    func update(selectionMode: Bool) {
        if !selectionMode { rangeSelection = nil }
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

extension FolderListModel {
    /// In a folder's detail list a tapped row opens its item and stays unselected: the item to
    /// open, or `nil` in a root list or without a selection. Clears `selected` and
    /// `listSelection` together. A row id left in `listSelection` was written back into
    /// `selected` by the list selection observer, which opened the item a second time.
    func takeDetailSelection() -> UUID? {
        guard parentModel != nil, let itemId = selectedItemId else { return nil }
        selected = nil
        resetListSelection()
        return itemId
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
    public init(id: UUID, source: ItemRowModel, level: Int, isShown: Bool, lastIsShown: Bool = false) {
        self.id = id
        self.source = source
        self.level = level
        self.isOpen = isShown
        self.lastIsOpen = lastIsShown
    }
    
    // identifier
    public let id: UUID
    /// For reference it could be link to another module. Changes only when the entry the row stands
    /// for moved to another item (`FolderListControllable.mapResult` follows it).
    public internal(set) var source: ItemRowModel
    public var level: Int

    // display state
    public var isOpen: Bool
    public var lastIsOpen: Bool = false
    
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

    /// True when this row shows an entry of its own item. A member row of a folder or collection
    /// also carries an `entryId`, the entry of its parent that links to it, and is an item row.
    var isEntryRow: Bool {
        guard let entryId = source.entryId else { return false }
        return model?.entries.contains(where: { $0.id == entryId }) == true
    }

    /// Creates an independent copy of this item and its entire children tree.
    /// Used by `resetDetailList(parentModel:)` to seed a `detailListModel` with pre-loaded items from the
    /// main list without sharing references — each model can evolve independently.
    public func deepCopy() -> FolderListItemModel {
        let copy = FolderListItemModel(
            id: id,
            source: source,
            level: level,
            isShown: isOpen,
            lastIsShown: lastIsOpen
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
        hasher.combine(level)
    }

    public static func == (lhs: FolderListItemModel, rhs: FolderListItemModel) -> Bool {
        // Rebuilt lists reuse the cached row instances, and `@Observable` compares the old and
        // new `list` on every assignment: without this, each comparison walked every row's
        // whole children tree. See CODE_AUDIT_Folder §7.4.
        if lhs === rhs { return true }
        return lhs.id == rhs.id &&
        lhs.source == rhs.source &&
        lhs.level == rhs.level &&
        lhs.isOpen == rhs.isOpen &&
        lhs.lastIsOpen == rhs.lastIsOpen &&
        lhs.children == rhs.children
    }
}

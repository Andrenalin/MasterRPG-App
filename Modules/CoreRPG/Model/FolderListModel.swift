// @copyright André Trettin

import SwiftUI

@Observable
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

    // Search
    @ObservationIgnored var searchTask: Task<Void, Never>? = nil
    public var searchExpandsEntries: Bool = false

    // MARK: - Display list
    public var list: [FolderListItemModel] = []
    public var cacheListModels: [UUID: FolderListItemModel] = [:]

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
    public var selection: [UUID]
    public var selected: UUID?
    public var listSelection: Set<UUID>

    // MARK: - Scroll
    
    var scrollId: UUID?
    
    // MARK: - ListModels
    @ObservationIgnored var subListModel: FolderListModel?
    
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
            if list[index].source.itemId == selected {
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
        selected = selectedItemId
    }

    var selectedItemId: UUID? {
        selected
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
    public let level: Int

    // display state
    public var isOpen: Bool
    public var lastIsOpen: Bool = false
    public var isHidden: Bool = false
    public var isFolded: Bool = false
    
    // children
    public var children: [FolderListItemModel] = []
    
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

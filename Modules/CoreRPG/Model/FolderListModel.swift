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

    // MARK: - Selection
    private var isSelectionMode: Bool
    public var selection: [UUID]
    public var selected: UUID?
    public var listSelection: Set<UUID>

    // MARK: - Scroll
    
    var scrollId: UUID?
    
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
    
    func resetDetailList(parentModel: any ItemDataAccessable) {
        if detailListModel == nil {
            detailListModel = FolderListModel(parentModel: parentModel, navigationModel: navigationModel)
        } else {
            detailListModel?.resetListModel(parentModel: parentModel)
        }
        detailListModel?.cacheListModels[parentModel.id] = cacheListModels[parentModel.id]
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

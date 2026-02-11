// @copyright André Trettin

import SwiftUI

@Observable
public final class FolderListModel {
    public init(isSelectionMode: Bool = false, selection: [String] = []) {
        self.isSelectionMode = isSelectionMode
        self.selection = selection
        self.listSelection = Set(selection)
        update(selection: Set(selection))
    }
    
    public init(parentModel: (any ItemDataAccessable)?) {
        self.parentModel = parentModel
        self.selectedParentId = parentModel?.id
        self.isSelectionMode = false
        self.selection = []
        self.listSelection = []
    }
    
    // MARK: - Items
    @ObservationIgnored var parentModel: (any ItemDataAccessable)?
    
    @ObservationIgnored var updatedOnce: Bool = false
    @ObservationIgnored var originalItems: [ListItemModel] = []
    @ObservationIgnored var parentOriginalItems: [ListItemModel] = []
    
    public var displayedItems: [ListItemModel] = []
    public var displayedParentItems: [ListItemModel] = []
        
    var addedModelId: UUID?
    
    // MARK: - List navigation
    public var selectedParentId: UUID?
    public var lastFolderId: UUID?
    private var subItemModels: [UUID: [UUID: ListSubItemModel]] = [:]
    var level: Int = 0
        
    public func isFolderOpen(itemId: UUID, entryId: UUID?) -> Bool {
        if let models = subItemModels[itemId], let model = models[entryId ?? itemId] {
            return model.isOpen
        }
        return false
    }
    
    func toggleFolder(itemId: UUID, entryId: UUID?) {
        let model = subItemModel(for: itemId, entryId: entryId, isOpen: false, level: level)
        model.isOpen.toggle()
    }
    
    func subItemModel(for itemId: UUID, entryId: UUID?, isOpen: Bool, level: Int) -> ListSubItemModel {
        if let models = subItemModels[itemId], let model = models[entryId ?? itemId] {
           return model
        }
        let model = ListSubItemModel(id: itemId, entryId: entryId, isOpen: isOpen, level: level)
        var models = subItemModels[itemId, default: [:]]
        models[entryId ?? itemId] = model
        subItemModels[itemId] = models
        return model
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
        selected = displayedItems.first(where: { $0.model.id == selectedItemId })?.id
    }

    var selectedItemId: UUID? {
        displayedItems.first(where: { $0.id == selected })?.model.id
    }

    var selectedModel: (any ItemDataAccessable)? {
        displayedItems.first(where: { $0.id == selected })?.model
    }

    var selectionItemIds: [UUID] {
        selection.compactMap { selected in
            displayedItems.first(where: { $0.id == selected })?.model.id
        }
    }
        
    func ids(selectedItemIds: [UUID]) -> [String] {
        selectedItemIds.compactMap { itemId -> String? in
            displayedItems.first(where: { $0.model.id == itemId })?.id
        }
    }
}

// MARK: - Navigation

public extension FolderListModel {
    func resetListModel() {
        resetListSelection()
        update(selection: Set())
        subListModel = nil
    }
}

@Observable
final class ListSubItemModel {
    init(id: UUID, entryId: UUID?, isOpen: Bool = false, level: Int = 0) {
        self.id = id
        self.entryId = entryId
        self.isOpen = isOpen
        self.level = 0
    }
    
    let id: UUID
    let entryId: UUID?
    var isOpen: Bool
    let level: Int
}


@Observable
public final class ListItemModel: Identifiable {
    public init(id: String, model: any ItemDataAccessable, isOpen: Bool = false, entryId: UUID? = nil, level: Int = 0) {
        self.id = id
        self.model = model
        self.isOpen = isOpen
        self.entryId = entryId
        self.level = level
    }

    public let id: String
    let model: any ItemDataAccessable
    var isOpen: Bool
    let entryId: UUID?
    public let level: Int
}

extension ListItemModel: Equatable {
    public static func == (lhs: ListItemModel, rhs: ListItemModel) -> Bool {
        lhs.id == rhs.id
        && lhs.model.id == rhs.model.id
        && lhs.isOpen == rhs.isOpen
        && lhs.entryId == rhs.entryId
        && lhs.level == rhs.level
    }
}

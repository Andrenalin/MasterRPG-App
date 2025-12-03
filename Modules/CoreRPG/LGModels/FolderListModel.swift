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
        self.isSelectionMode = false
        self.selection = []
        self.listSelection = []
    }
    
    // MARK: - Items
    public var parentModel: (any ItemDataAccessable)?
    
    @ObservationIgnored var originalItems: [ListItemModel] = []
    public var displayedItems: [ListItemModel] = []
    
    var addedModelId: UUID?
    
    // MARK: - List navigation
    public var selectedParentId: UUID?
    public var lastFolderId: UUID?
    private var subItemModels: [UUID: ListSubItemModel] = [:]
    var level: Int = 0
        
    public func isFolderOpen(itemId: UUID) -> Bool {
        subItemModels[itemId]?.isOpen ?? false
    }
    
    func toggleFolder(itemId: UUID) {
        guard let model = subItemModels[itemId] else {
            subItemModels[itemId] = ListSubItemModel(id: itemId, isOpen: true, level: level)
            return
        }
        model.isOpen.toggle()
    }
    
    func subItemModel(for itemId: UUID) -> ListSubItemModel {
        if let model = subItemModels[itemId] {
           return model
        }
        let model = ListSubItemModel(id: itemId, level: level + 1)
        subItemModels[itemId] = model
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
    
    func item(modelId: UUID?) -> ListItemModel? {
        guard let modelId else { return nil }
        return displayedItems.first(where: { $0.model.id == modelId })
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
    init(id: UUID, isOpen: Bool = false, level: Int = 0) {
        self.id = id
        self.isOpen = isOpen
        self.level = 0
    }
    
    var id: UUID
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

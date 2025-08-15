// @copyright André Trettin

import SwiftUI

@Observable @MainActor
public final class ListModel {
    public init(isSelectionMode: Bool = false, selection: [UUID] = []) {
        self.isSelectionMode = isSelectionMode
        self.selection = selection
        self.listSelection = Set(selection)
        update(selection: Set(selection))
    }
    
    public init(listModel: ListModel, parentId: UUID?, lastFolderId: UUID?) {
        self.selectedParentId = parentId
        self.lastFolderId = lastFolderId
        self.isSelectionMode = false
        self.selection = []
        self.listSelection = []
    }
    
    // MARK: - Items
//    var items: [Model] = []
//    func update(items: [Model]) {
//        
//    }
    //public var items:
    
    // MARK: - List navigation
    public var selectedParentId: UUID?
    public var lastFolderId: UUID?
    private var subItemModels: [UUID: ListSubItemModel] = [:]
    var level: Int = 0
    
    func isFolderOpen(id: UUID) -> Bool {
        subItemModels[id]?.isOpen ?? false
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
    public var selection: [UUID]
    public var selected: UUID?
    public var listSelection: Set<UUID>
    
    public var multiSelection: Bool = true
    
    // MARK: - ListModels
    @ObservationIgnored
    private var subListModel: ListModel?
}

// MARK: - Selection

public extension ListModel {
    func resetListSelection() {
        listSelection = []
    }

    func update(selectionMode: Bool) {
        isSelectionMode = selectionMode
        if isSelectionMode {
            selection = []
        } else if let selected {
            selection = [selected]
        }
    }

    func update(selection: Set<UUID>) {
        if isSelectionMode {
            self.selection = Array(selection)
        } else {
            selected = selection.first
        }
    }
}

// MARK: - Navigation

public extension ListModel {
    func lastSubListModel(for parentId: UUID, parentIsFolder: Bool) -> ListModel {
        guard let subListModel, subListModel.selectedParentId == parentId else {
            let listModel = ListModel(listModel: self, parentId: parentId, lastFolderId: parentIsFolder ? parentId : lastFolderId)
            self.subListModel = listModel
            return listModel
        }
        return subListModel
    }

    func lastSubListModel() -> ListModel {
        guard let listModel = subListModel else {
            return self
        }
        return listModel.lastSubListModel()
    }
    
    func resetListModel() {
        selected = nil
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

struct ItemListModel<Model>: Identifiable {
    let id: UUID
    let model: Model
    let isOpen: Bool
    let level: Int
}

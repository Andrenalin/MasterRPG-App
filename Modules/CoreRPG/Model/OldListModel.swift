// @copyright André Trettin

import SwiftUI

@Observable @MainActor
public final class OldListModel {
    public init(isSelectionMode: Bool = false, selection: [String] = []) {
        self.isSelectionMode = isSelectionMode
        self.selection = selection
        self.listSelection = Set(selection)
        update(selection: Set(selection))
    }
    
    public init(listModel: OldListModel, parentId: UUID?, lastFolderId: UUID?) {
        self.selectedParentId = parentId
        self.lastFolderId = lastFolderId
        self.isSelectionMode = false
        self.selection = []
        self.listSelection = []
    }
    
    // MARK: - Items
    public var originalItems: [OldListItemModel] = []
    public var displayedItems: [OldListItemModel] = []
    
    //public var items:
    
    // MARK: - List navigation
    public var selectedParentId: UUID?
    public var lastFolderId: UUID?
    private var subItemModels: [UUID: OldListSubItemModel] = [:]
    var level: Int = 0
    
    
    public func isFolderOpen(itemId: UUID) -> Bool {
        subItemModels[itemId]?.isOpen ?? false
    }
    
    func toggleFolder(itemId: UUID) {
        guard let model = subItemModels[itemId] else {
            subItemModels[itemId] = OldListSubItemModel(id: itemId, isOpen: true, level: level)
            return
        }
        model.isOpen.toggle()
    }
    
    func subItemModel(for itemId: UUID) -> OldListSubItemModel {
        if let model = subItemModels[itemId] {
           return model
        }
        let model = OldListSubItemModel(id: itemId, level: level + 1)
        subItemModels[itemId] = model
        return model
    }
        
    // MARK: - Selection
    private var isSelectionMode: Bool
    public var selection: [String]
    public var selected: String?
    public var listSelection: Set<String>

    public var multiSelection: Bool = true
    
    // MARK: - ListModels
    @ObservationIgnored
    var subListModel: OldListModel?
}

// MARK: - Selection

public extension OldListModel {
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

    func update(selection: Set<String>) {
        if isSelectionMode {
            self.selection = Array(selection)
        } else {
            selected = selection.first
        }
    }

    func set(selectedItemId: UUID) {
        selected = displayedItems.first(where: { $0.itemId == selectedItemId })?.id
    }

    var selectedItemId: UUID? {
        displayedItems.first(where: { $0.id == selected })?.itemId
    }

    var selectionItemIds: [UUID] {
        selection.compactMap { selected in
            displayedItems.first(where: { $0.id == selected })?.itemId
        }
    }
}

// MARK: - Navigation

public extension OldListModel {
    func lastSubListModel(for parentId: UUID, parentIsFolder: Bool) -> OldListModel {
        guard let subListModel, subListModel.selectedParentId == parentId else {
            let listModel = OldListModel(listModel: self, parentId: parentId, lastFolderId: parentIsFolder ? parentId : lastFolderId)
            self.subListModel = listModel
            return listModel
        }
        return subListModel
    }

    func lastSubListModel() -> OldListModel {
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
final class OldListSubItemModel {
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


@Observable @MainActor
public final class OldListItemModel: Identifiable {
    public init(id: String, itemId: UUID, isOpen: Bool = false, level: Int = 0, isSpecial: Bool = false, name: String, information: String, tags: [String], parentId: UUID? = nil) {
        self.id = id
        self.itemId = itemId
        self.isOpen = isOpen
        self.level = level
        self.isSpecial = isSpecial
        self.name = name
        self.information = information
        self.tags = tags
        self.parentId = parentId
    }
    
    public let id: String
    let itemId: UUID
    var isOpen: Bool
    public let level: Int
    
    public let name: String
    public let information: String
    public let isSpecial: Bool
    public let tags: [String]
    public let parentId: UUID?
}

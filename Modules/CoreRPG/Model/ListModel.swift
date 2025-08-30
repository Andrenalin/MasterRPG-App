// @copyright André Trettin

import SwiftData
import SwiftUI

@Observable
public final class ListModel {
    public init(isSelectionMode: Bool = false, selection: [String] = []) {
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
    @ObservationIgnored var originalItems: [ListItemModel] = []
    public var displayedItems: [ListItemModel] = [] {
        willSet {
            print("will set displayedItems on \(selectedParentId?.uuidString ?? "No parent") \(displayedItems.count)")
        }
        didSet {
            print("did set displayedItems on \(selectedParentId?.uuidString ?? "No parent") \(displayedItems.count)")
        }
    }
    
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
    @ObservationIgnored var subListModel: ListModel?
}

// MARK: - Items
extension ListModel {
    func deleteItems(offsets: IndexSet) {
        displayedItems.remove(atOffsets: offsets)
    }
    
    func item(modelId: UUID?) -> ListItemModel? {
        guard let modelId else { return nil }
        return displayedItems.first(where: { $0.model.id == modelId })
    }
}

// MARK: - Selection

public extension ListModel {
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
            selected <=> selection.first
        }
    }

    func set(selectedItemId: UUID) {
        selected = displayedItems.first(where: { $0.model.id == selectedItemId })?.id
    }

    var selectedItemId: UUID? {
        displayedItems.first(where: { $0.id == selected })?.model.id
    }

    var selectedModel: ItemDataModel? {
        displayedItems.first(where: { $0.id == selected })?.model
    }

    var selectionItemIds: [UUID] {
        selection.compactMap { selected in
            displayedItems.first(where: { $0.id == selected })?.model.id
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
    public init(id: String, model: ItemDataModel, isOpen: Bool = false, level: Int = 0) {
        self.id = id
        self.model = model
        self.isOpen = isOpen
        self.level = level
    }

    public let id: String
    let model: ItemDataModel
    var isOpen: Bool
    public let level: Int
}

extension ListItemModel: Equatable {
    public static func == (lhs: ListItemModel, rhs: ListItemModel) -> Bool {
        lhs.id == rhs.id
        && lhs.model.id == rhs.model.id
        && lhs.isOpen == rhs.isOpen
        && lhs.level == rhs.level
    }
}

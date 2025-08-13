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
    
    public init(listModel: ListModel, parentId: UUID, lastFolderId: UUID?) {
        self.selectedParentId = parentId
        self.lastFolderId = lastFolderId
        self.isSelectionMode = false
        self.selection = []
        self.listSelection = []
        self.displayMode = listModel.displayMode
        self.listMode = .folder
    }
    
    // MARK: - Items
    
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
    
    public func resetSubListModels() {
        listModels = [:]
    }
    
    // MARK: - Selection
    private(set) public var isSelectionMode: Bool
    public var selection: [UUID]
    public var selected: UUID?
    public var listSelection: Set<UUID>
    
    public var multiSelection: Bool = true
    
    // MARK: - ListModels
    private var listModels: [UUID: ListModel] = [:]
    
    // MARK: - Display Mode
    public enum DisplayMode: Int, Equatable, Hashable, Codable, Sendable {
        case compact
        case medium
        case regular
    }
    public var displayMode: DisplayMode = .medium
    
    public var isCompactDisplayMode: Bool {
        get { displayMode == .compact }
        set {
            guard newValue, displayMode != .compact else { return }
            displayMode = .compact
        }
    }
    public var isMediumDisplayMode: Bool {
        get { displayMode == .medium }
        set {
            guard newValue, displayMode != .medium else { return }
            displayMode = .medium
        }
    }
    public var isRegularDisplayMode: Bool {
        get { displayMode == .regular }
        set {
            guard newValue, displayMode != .regular else { return }
            displayMode = .regular
        }
    }
    
    // MARK: - List Mode
    public enum ListMode: Int, Equatable, Hashable, Codable, Sendable {
        case list
        case folder
    }
    public var listMode: ListMode = .list

    public var isListMode: Bool {
        get { listMode == .list }
        set {
            guard newValue, listMode != .list else { return }
            listMode = .list
        }
    }
    public var isFolderMode: Bool {
        get { listMode == .folder }
        set {
            guard newValue, listMode != .folder else { return }
            listMode = .folder
        }
    }
    
    var isPadStyle = false
}

// MARK: - Selection

public extension ListModel {
    func resetListSelection() {
        listSelection = []
    }

    func toogleSelectionMode() {
        isSelectionMode.toggle()
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

// MARK: - ListModels

public extension ListModel {
    func listModel(for parentId: UUID, parentIsFolder: Bool) -> ListModel {
        guard let model = listModels[parentId] else {
            let listModel = ListModel(listModel: self, parentId: parentId, lastFolderId: parentIsFolder ? parentId : lastFolderId)
            listModels[parentId] = listModel
            return listModel
        }
        return model
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

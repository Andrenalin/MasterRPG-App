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
    
    // MARK: - List navigation
    public var selectedParentId: UUID?
    var subItemModels: [UUID: ListSubItemModel] = [:]
    
    // MARK: - Selection
    private(set) public var isSelectionMode: Bool
    public var selection: [UUID]
    public var selected: UUID?
    public var listSelection: Set<UUID>
    
    public var focusSelectedItem: Binding<UUID>?
    
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
            if let selected {
                focusSelectedItem = .constant(selected)
            } else {
                focusSelectedItem = nil
            }
        }
    }
}


@Observable
final class ListSubItemModel {
    init(id: UUID, isOpen: Bool = false) {
        self.id = id
        self.isOpen = isOpen
    }
    
    var id: UUID
    var isOpen: Bool
}

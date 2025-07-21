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
    
    private(set) public var isSelectionMode: Bool
    var splitList: Bool = false
    public var listSelection: Set<UUID>
    public var selection: [UUID]
    public var selected: UUID?

    public var currentMenuSelection: UUID?

    public func resetListSelection() {
        listSelection = []
    }

    public func update(selection: Set<UUID>) {
        if isSelectionMode {
            self.selection = Array(selection)
        } else {
            selected = selection.first
        }
    }
    
    public func toogleSelectionMode() {
        isSelectionMode.toggle()
        if isSelectionMode {
            selection = []
        } else if let selected {
            selection = [selected]
        }
    }
}


// @copyright André Trettin

import SwiftUI

@Observable @MainActor
public final class ListModel {
    public init(isSelectionMode: Bool = false, selection: [UUID] = []) {
        self.isSelectionMode = isSelectionMode
        self.selection = selection
    }
    
    private(set) public var isSelectionMode: Bool
    public var selection: [UUID]
    public var selected: UUID?
    
    public var splitList: Bool = false
    
    public func update(listSelection: Set<UUID>) {
        if isSelectionMode {
            selection = Array(listSelection)
        } else {
            selected = listSelection.first
        }
    }
    
    public func toogleSelectionMode() {
        isSelectionMode.toggle()
        selection = []
    }
}


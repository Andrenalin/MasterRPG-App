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

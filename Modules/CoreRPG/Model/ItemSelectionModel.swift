// @copyright André Trettin

import Foundation

@MainActor @Observable
public final class ItemSelectionModel {
    public init(selection: [WindowItemSelection] = [], isSingleSelection: Bool = true, allowCollections: Bool = false, allowEntrySelection: Bool = false, onlyEntrySelection: Bool = false) {
        self.selection = selection
        self.isSingleSelection = isSingleSelection
        self.allowCollections = allowCollections
        self.allowEntrySelection = allowEntrySelection
        self.onlyEntrySelection = onlyEntrySelection
    }
    
    public var selection: [WindowItemSelection] = []
    public var isSingleSelection: Bool = true
    public var allowCollections: Bool = false
    public var allowEntrySelection: Bool = false
    public var onlyEntrySelection: Bool = false
    public var onlyChildrenFrom: UUID? = nil
    
    public var itemId: UUID? {
        selection.first?.itemId
    }
    
    public func toggleSelection(itemId: UUID, isCollection: Bool) {
        guard allowCollections == true || isCollection == false else { return }
        if let index = selection.firstIndex(where: { $0.itemId == itemId }) {
            selection.remove(at: index)
        } else {
            if isSingleSelection {
                selection = [WindowItemSelection(itemId: itemId)]
            } else {
                selection.append(WindowItemSelection(itemId: itemId))
            }
        }
    }
    
    public func resetSelection(itemId: UUID?) {
        guard let itemId else {
            selection <=> []
            return
        }
        selection <=> [WindowItemSelection(itemId: itemId)]
    }

    public func resetSelection(selectionIds: [UUID]) {
        selection <=> selectionIds.map { WindowItemSelection(itemId: $0) }
    }

    func canSelect(isCollection: Bool) -> Bool {
        allowCollections || !isCollection
    }
}

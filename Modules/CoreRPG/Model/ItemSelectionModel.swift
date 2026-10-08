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

    public var entryId: UUID? {
        selection.first?.entryId
    }

    public func toggleSelection(itemId: UUID, entryId: UUID?, isCollection: Bool) {
        guard allowCollections == true || isCollection == false else { return }
        guard (onlyEntrySelection && entryId != nil) || onlyEntrySelection == false else { return }
        if let index = selection.firstIndex(where: { $0.itemId == itemId && $0.entryId == entryId }) {
            selection.remove(at: index)
        } else {
            if isSingleSelection {
                selection = [WindowItemSelection(itemId: itemId, entryId: entryId)]
            } else {
                selection.append(WindowItemSelection(itemId: itemId, entryId: entryId))
            }
        }
    }
    
    public func resetSelection(itemId: UUID?, entryId: UUID?) {
        guard let itemId else {
            selection <=> []
            return
        }
        selection <=> [WindowItemSelection(itemId: itemId, entryId: entryId)]
    }

    public func resetSelection(selectionIds: [UUID]) {
        selection <=> selectionIds.map { WindowItemSelection(itemId: $0) }
    }

    func canSelect(isCollection: Bool, entryId: UUID?) -> Bool {
        (allowCollections || !isCollection) && (!onlyEntrySelection || onlyEntrySelection && entryId != nil)
    }

    /// Whether a link list of `type` over `module` shows the entries of its items: their rows
    /// and the chevron that reveals them. Folders and collections keep their chevron, which
    /// reveals items.
    /// - A selection list hides entries that cannot be selected.
    /// - An inspector hides the entries of characters, which other modules link as a whole;
    ///   the Character module allows entry selection and scopes its inspector to the selected
    ///   character through `onlyChildrenFrom`.
    func showsEntries(in type: LinkRootType, module: NetworkModules) -> Bool {
        if allowEntrySelection || onlyEntrySelection { return true }
        switch type {
        case .selection, .selectionInline: return false
        case .inspector: return module != .value
        case .window: return true
        }
    }
}

// @copyright André Trettin

import SwiftUI

@MainActor @Observable
public final class RemoveEntryListModel {
    public init(removeItems: [ItemRowModel] = []) {
        self.removeItems = removeItems
        self.linkTree = []
    }

    public var removeItems: [ItemRowModel] = []
    var linkTree: [RemoveLinkTreeModel] = []

    /// Counts the deletions handed to the removal panel. A panel only clears the list it was
    /// opened for: a second Delete during the first panel's dismissal animation replaced the
    /// list, and the first panel's disappearance then emptied it under the second panel.
    /// See CODE_AUDIT_21 §5.31.
    @ObservationIgnored private(set) var presentation = 0

    /// Hands `items` to the removal panel that is opened next.
    public func present(_ items: [ItemRowModel]) {
        presentation += 1
        removeItems = items
    }
}

struct RemoveLinkTreeModel: Identifiable {
    var item: ItemRowModel
    var link: AffectedItemModel?
    var canRemove: Bool
    var counter: Int
    
    var id: UUID {
        item.entryId ?? item.itemId
    }
}

public struct AffectedItemModel: Equatable, Hashable, Identifiable, Sendable {
    public init(id: UUID, name: String, entryName: String? = nil, module: NetworkModules) {
        self.id = id
        self.name = name
        self.entryName = entryName
        self.module = module
    }
    
    public let id: UUID
    public let name: String
    public let entryName: String?
    public let module: NetworkModules
    
    var title: String {
        guard let entryName else {
            return name
        }
        return "\(name) --- \(entryName)"
    }
}

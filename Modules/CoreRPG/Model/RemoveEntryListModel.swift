// @copyright André Trettin

import SwiftUI

@MainActor @Observable
public final class RemoveEntryListModel {
    public init(removeItems: [ItemRowModel] = []) {
        self.removeItems = removeItems
        self.linkTree = []
    }

    public var removeItems: [ItemRowModel] = []
    var showDeleteAlert: Bool = false
    var linkTree: [RemoveLinkTreeModel] = []
}

struct RemoveLinkTreeModel: Identifiable {
    var item: ItemRowModel
    var link: AffectedItemModel?
    var canRemoved: Bool
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

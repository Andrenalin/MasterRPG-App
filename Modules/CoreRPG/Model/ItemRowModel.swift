// @copyright André Trettin

import Foundation

public struct ItemRowModel: Equatable, Hashable, Codable, Sendable {
    public init(itemId: UUID, entryId: UUID? = nil, typeId: NetworkModules) {
        self.itemId = itemId
        self.entryId = entryId
        self.typeId = typeId
    }

    public let itemId: UUID
    public let entryId: UUID?
    public let typeId: NetworkModules

    static let empty = ItemRowModel(itemId: UUID(), entryId: nil, typeId: .none)
}

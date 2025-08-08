// @copyright André Trettin

import Foundation

public struct ItemSelectionModel: Equatable, Hashable, Codable {
    public init(itemId: UUID, entryId: UUID? = nil) {
        self.itemId = itemId
        self.entryId = entryId
    }
    public let itemId: UUID
    public let entryId: UUID?
}


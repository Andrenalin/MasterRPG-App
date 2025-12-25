// @copyright André Trettin

import SwiftUI

public struct ItemSelection: Equatable, Hashable, Codable {
    public init(itemId: UUID, entryId: UUID?) {
        self.itemId = itemId
        self.entryId = entryId
    }
    public let itemId: UUID
    public let entryId: UUID?
}

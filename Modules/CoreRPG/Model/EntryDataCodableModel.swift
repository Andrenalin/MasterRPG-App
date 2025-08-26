// @copyright André Trettin

import Foundation
import SwiftData

public struct EntryDataCodableModel: Codable, Hashable, Equatable, Sendable {
    public init(id: UUID, index: Int, parentId: UUID, childId: UUID) {
        self.id = id
        self.index = index
        self.parentId = parentId
        self.childId = childId
    }
    
    public let id: UUID
    public let index: Int
    public let parentId: UUID
    public let childId: UUID
}
